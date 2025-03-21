#!/usr/bin/env python3
"""
CrowdStrike CSPM AWS Cost Estimator

This script estimates the costs associated with deploying CrowdStrike Falcon CSPM
across multiple AWS accounts in an organization.

The estimator analyzes actual AWS CloudTrail usage patterns to predict the costs
of deploying CrowdStrike CSPM, focusing on:
1. EventBridge event delivery costs ($1.00 per million events)
2. Data egress costs (varies by region)
3. Lambda function costs (minimal)
4. DSPM (Data Security Posture Management) costs
5. Snapshot scanning costs
6. Additional AWS service costs if needed

Usage:
    python crowdstrike_cost_estimator.py [--regions REGION [REGION ...]] 
                                       [--output OUTPUT]
                                       [--all-regions]
                                       [--include-dspm]
                                       [--include-snapshot]

Requirements:
    - aws_creds.py script in the same directory
    - boto3, pandas libraries
    - AWS credentials with organization access
    
Author: Your Organization
Version: 2.0.0
"""

import argparse
import csv
from datetime import datetime, timedelta
import pandas as pd
import boto3
import threading
import sys
import os
import json
from concurrent.futures import ThreadPoolExecutor

# Threading lock for console output
print_lock = threading.Lock()

class CrowdStrikeCostEstimator:
    """
    Main class for estimating CrowdStrike CSPM costs across AWS accounts.
    
    This class handles:
    - AWS authentication via aws_creds.py
    - AWS Organization account discovery
    - Cross-account access via role assumption
    - CloudTrail event volume estimation
    - Data transfer volume estimation
    - Cost calculations based on AWS pricing
    - Report generation with account and region breakdowns
    
    The estimator focuses on CrowdStrike components that affect AWS costs:
    - EventBridge rules for CloudTrail events
    - Data egress from AWS to CrowdStrike
    - Lambda functions for processing
    - DSPM scanning costs (optional)
    - Snapshot scanning costs (optional)
    
    Cost estimation methodology:
    1. Primary: Use actual metrics when available
    2. Secondary: Estimate based on related metrics 
    3. Tertiary: Estimate based on resource counts
    4. Fallback: Use conservative default assumptions
    """
    def __init__(self, regions=None, output_file="crowdstrike_cost_estimate.csv", 
                 include_all_regions=False, include_dspm=False, include_snapshot=False):
        """
        Initialize the cost estimator.
        
        Args:
            regions (list): AWS regions to analyze (if None and all_regions=False, defaults to us-east-1)
            output_file (str): Path to output CSV file
            include_all_regions (bool): Whether to analyze all enabled regions for each account
            include_dspm (bool): Whether to include DSPM cost estimates
            include_snapshot (bool): Whether to include Snapshot cost estimates
        """
        self.regions = regions
        self.output_file = output_file
        self.include_all_regions = include_all_regions
        self.include_dspm = include_dspm
        self.include_snapshot = include_snapshot
        self.accounts = []  # Will store account IDs and names
        self.results = []   # Will store cost estimation results
        self.all_available_regions = []  # Will be populated with all available AWS regions
        
        # Call external script to establish AWS session with role assumption
        print("Establishing AWS session...")
        try:
            import aws_creds
            self.base_session = aws_creds.get_session()
            
            if not self.base_session:
                print("Failed to establish AWS session. Exiting.")
                sys.exit(1)
                
            print("AWS session established successfully.")
        except ImportError:
            print("Error: aws_creds.py not found. Please ensure it's in the same directory.")
            sys.exit(1)
        except Exception as e:
            print(f"Error establishing AWS session: {e}")
            sys.exit(1)
        
        # Get all available AWS regions
        try:
            ec2 = self.base_session.client('ec2', region_name='us-east-1')
            self.all_available_regions = [region['RegionName'] for region in ec2.describe_regions()['Regions']]
            print(f"Found {len(self.all_available_regions)} available AWS regions")
        except Exception as e:
            print(f"Error retrieving available regions: {e}")
            self.all_available_regions = [
                "us-east-1", "us-east-2", "us-west-1", "us-west-2",
                "ca-central-1", "eu-west-1", "eu-west-2", "eu-west-3",
                "eu-central-1", "eu-north-1", "ap-northeast-1",
                "ap-northeast-2", "ap-northeast-3", "ap-southeast-1",
                "ap-southeast-2", "ap-south-1", "sa-east-1"
            ]
            print(f"Using default list of {len(self.all_available_regions)} AWS regions")
        
        # Determine which regions to analyze
        if self.include_all_regions:
            self.regions = self.all_available_regions
            print(f"Will analyze all {len(self.regions)} available regions")
        elif not self.regions:
            self.regions = ["us-east-1"]
            print(f"Will analyze default region: {self.regions[0]}")
        else:
            print(f"Will analyze {len(self.regions)} specified regions: {', '.join(self.regions)}")
        
        # Get account information from Organizations
        try:
            org_client = self.base_session.client('organizations')
            paginator = org_client.get_paginator('list_accounts')
            
            all_accounts = []
            for page in paginator.paginate():
                all_accounts.extend(page['Accounts'])
                
            self.accounts = [{'id': account['Id'], 'name': account['Name']} 
                            for account in all_accounts 
                            if account['Status'] == 'ACTIVE']
            
            print(f"Found {len(self.accounts)} active accounts in the organization")
        except Exception as e:
            print(f"Error accessing organization accounts: {e}")
            # Use current account as fallback
            sts = self.base_session.client('sts')
            account_id = sts.get_caller_identity()['Account']
            account_aliases = self.base_session.client('iam').list_account_aliases().get('AccountAliases', [''])
            account_name = account_aliases[0] if account_aliases else account_id
            self.accounts = [{'id': account_id, 'name': account_name}]
    
    def _get_account_session(self, account_id):
        """
        Get a boto3 session for accessing resources in a specific account.
        
        This method handles cross-account access by assuming roles with appropriate
        permissions. It tries multiple common cross-account role names if the
        primary role assumption fails.
        
        Args:
            account_id (str): AWS account ID to access
            
        Returns:
            boto3.Session: Authenticated session for the specified account, or None if access fails
        """
        # If current account, use base session
        if account_id == self.base_session.client('sts').get_caller_identity()['Account']:
            return self.base_session
        
        # For cross-account access, assume role
        try:
            # Modify this role name if your organization uses a different convention
            role_arn = f"arn:aws:iam::{account_id}:role/OrganizationAccountAccessRole"
            sts = self.base_session.client('sts')
            
            response = sts.assume_role(
                RoleArn=role_arn,
                RoleSessionName=f"CrowdStrikeCostEstimation-{account_id}"
            )
            
            return boto3.Session(
                aws_access_key_id=response['Credentials']['AccessKeyId'],
                aws_secret_access_key=response['Credentials']['SecretAccessKey'],
                aws_session_token=response['Credentials']['SessionToken']
            )
        except Exception as e:
            with print_lock:
                print(f"Error assuming role for account {account_id}: {e}")
                print(f"Trying alternative role names...")
            
            # Try alternative role names
            for role_name in ["AWSControlTowerExecution", "OrganizationAccountAccess"]:
                try:
                    role_arn = f"arn:aws:iam::{account_id}:role/{role_name}"
                    response = sts.assume_role(
                        RoleArn=role_arn,
                        RoleSessionName=f"CrowdStrikeCostEstimation-{account_id}"
                    )
                    
                    return boto3.Session(
                        aws_access_key_id=response['Credentials']['AccessKeyId'],
                        aws_secret_access_key=response['Credentials']['SecretAccessKey'],
                        aws_session_token=response['Credentials']['SessionToken']
                    )
                except:
                    continue
            
            with print_lock:
                print(f"Could not assume role for account {account_id}. Skipping...")
            return None
    
    def get_enabled_regions_for_account(self, account_id):
        """
        Get the list of enabled regions for a specific account.
        
        Args:
            account_id (str): AWS account ID to check
            
        Returns:
            list: List of enabled AWS regions for the account
        """
        session = self._get_account_session(account_id)
        if session is None:
            return self.regions  # Fall back to specified regions
        
        try:
            # Check if account has EC2 global view enabled - if so, we can check from one region
            ec2 = session.client('ec2', region_name='us-east-1')
            try:
                response = ec2.describe_regions(AllRegions=True)
                regions = [region['RegionName'] for region in response['Regions'] if region.get('OptInStatus') != 'not-opted-in']
                return regions
            except Exception:
                # Fall back to checking each region individually
                pass
            
            # Check each region individually
            enabled_regions = []
            for region in self.all_available_regions:
                try:
                    regional_ec2 = session.client('ec2', region_name=region)
                    # Just making a simple call to verify the region is accessible
                    regional_ec2.describe_vpcs(MaxResults=5)
                    enabled_regions.append(region)
                except Exception:
                    # Skip regions that return access errors
                    continue
            
            return enabled_regions if enabled_regions else self.regions
        except Exception as e:
            with print_lock:
                print(f"Error determining enabled regions for account {account_id}: {e}")
            return self.regions  # Fall back to specified regions
    
    def estimate_cloudtrail_events(self, account_id, region):
        """
        Estimate the number of CloudTrail events per month for an account in a region.
        
        This method uses multiple approaches to estimate event volume:
        1. CloudWatch metrics for CloudTrail events (most accurate)
        2. CloudWatch metrics for API calls (fallback)
        3. Resource count-based estimation (second fallback)
        4. Default assumption (final fallback)
        
        Args:
            account_id (str): AWS account ID to analyze
            region (str): AWS region to analyze
            
        Returns:
            float: Estimated number of CloudTrail events per month
        """
        session = self._get_account_session(account_id)
        if session is None:
            return 1000000  # Default assumption
        
        try:
            cloudwatch = session.client('cloudwatch', region_name=region)
            
            # Get CloudTrail event count for the past 7 days
            now = datetime.utcnow()
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/CloudTrail',
                MetricName='Events',
                Dimensions=[{'Name': 'Region', 'Value': region}],
                StartTime=now - timedelta(days=7),
                EndTime=now,
                Period=86400,  # 1 day in seconds
                Statistics=['Sum']
            )
            
            # If data exists, calculate daily average and project to monthly
            if response['Datapoints']:
                total_events = sum(point['Sum'] for point in response['Datapoints'])
                days = len(response['Datapoints']) if len(response['Datapoints']) > 0 else 1
                daily_avg = total_events / days
                monthly_estimate = daily_avg * 30
                return monthly_estimate
            
            # If no CloudTrail data, try to estimate based on CloudWatch metrics for API calls
            try:
                # Check management API activity using CloudWatch metrics
                response = cloudwatch.get_metric_statistics(
                    Namespace='AWS/Usage',
                    MetricName='CallCount',
                    Dimensions=[
                        {'Name': 'Service', 'Value': 'ALL'},
                        {'Name': 'Type', 'Value': 'API'},
                        {'Name': 'Resource', 'Value': 'ALL'},
                        {'Name': 'Class', 'Value': 'ALL'}
                    ],
                    StartTime=now - timedelta(days=7),
                    EndTime=now,
                    Period=86400,
                    Statistics=['Sum']
                )
                
                if response['Datapoints']:
                    total_calls = sum(point['Sum'] for point in response['Datapoints'])
                    days = len(response['Datapoints']) if len(response['Datapoints']) > 0 else 1
                    daily_avg = total_calls / days
                    monthly_estimate = daily_avg * 30
                    # Only ~10-20% of API calls generate CloudTrail events
                    return monthly_estimate * 0.15
            except Exception:
                pass
            
            # If still no data, use account activity as a proxy
            try:
                # Get EC2 instance count as a proxy for account activity
                ec2 = session.client('ec2', region_name=region)
                response = ec2.describe_instances()
                instance_count = sum(len(reservation['Instances']) for reservation in response['Reservations'])
                
                # Get IAM user and role count
                iam = session.client('iam')
                user_count = len(iam.list_users()['Users'])
                role_count = len(iam.list_roles()['Roles'])
                
                # Rough estimate: 5,000 events per resource per month
                activity_factor = (instance_count + user_count + role_count) * 5000
                return max(activity_factor, 100000)
            except Exception:
                pass
            
            # Default fallback
            return 1000000  # Default assumption
        
        except Exception as e:
            with print_lock:
                print(f"Error estimating CloudTrail events for account {account_id} in {region}: {e}")
            return 1000000  # Default assumption
    
    def estimate_data_transfer(self, account_id, region):
        """
        Estimate the data transfer volume in GB per month from CloudTrail to CrowdStrike.
        
        This method calculates data egress based on:
        1. CloudWatch metrics for CloudTrail byte volume (most accurate)
        2. Event count multiplied by average event size (fallback)
        3. Default assumption (final fallback)
        
        Args:
            account_id (str): AWS account ID to analyze
            region (str): AWS region to analyze
            
        Returns:
            float: Estimated data transfer volume in GB per month
        """
        session = self._get_account_session(account_id)
        if session is None:
            return 5  # Default assumption (5 GB/month)
        
        try:
            cloudwatch = session.client('cloudwatch', region_name=region)
            
            # First try to get data from CloudTrail metrics
            now = datetime.utcnow()
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/CloudTrail',
                MetricName='BytesDelivered',
                Dimensions=[{'Name': 'Region', 'Value': region}],
                StartTime=now - timedelta(days=7),
                EndTime=now,
                Period=86400,  # 1 day in seconds
                Statistics=['Sum']
            )
            
            if response['Datapoints']:
                total_bytes = sum(point['Sum'] for point in response['Datapoints'])
                days = len(response['Datapoints']) if len(response['Datapoints']) > 0 else 1
                daily_avg_bytes = total_bytes / days
                monthly_estimate_gb = (daily_avg_bytes * 30) / (1024 * 1024 * 1024)
                return monthly_estimate_gb
            
            # If no data, estimate based on event count
            event_count = self.estimate_cloudtrail_events(account_id, region)
            # Average event size in KB (adjust based on your environment)
            avg_event_size_kb = 1.5
            monthly_estimate_gb = (event_count * avg_event_size_kb * 1024) / (1024 * 1024 * 1024)
            return monthly_estimate_gb
        
        except Exception as e:
            with print_lock:
                print(f"Error estimating data transfer for account {account_id} in {region}: {e}")
            return 5  # Default assumption (5 GB/month)
    
    def estimate_s3_buckets(self, account_id, region):
        """
        Count S3 buckets for DSPM cost estimation.
        
        This method counts S3 buckets in the specified region to estimate 
        DSPM scanning costs. S3 buckets are a key driver for DSPM costs.
        
        Args:
            account_id (str): AWS account ID to analyze
            region (str): AWS region to analyze
            
        Returns:
            dict: Dictionary containing bucket count and size estimates
                {
                    'count': Number of buckets,
                    'total_size_gb': Estimated total size in GB,
                    'avg_size_gb': Average bucket size in GB
                }
        """
        if not self.include_dspm:
            return {'count': 0, 'total_size_gb': 0, 'avg_size_gb': 0}
            
        session = self._get_account_session(account_id)
        if session is None:
            # Default assumptions:
            # - 10 buckets per account
            # - Average 50 GB per bucket
            return {'count': 10, 'total_size_gb': 500, 'avg_size_gb': 50}
        
        try:
            s3 = session.client('s3', region_name=region)
            cloudwatch = session.client('cloudwatch', region_name=region)
            
            # List all buckets
            buckets = s3.list_buckets()['Buckets']
            
            # Filter buckets in the specified region
            regional_buckets = []
            
            for bucket in buckets:
                try:
                    location = s3.get_bucket_location(Bucket=bucket['Name'])['LocationConstraint']
                    # AWS returns None for us-east-1
                    if location is None:
                        location = 'us-east-1'
                    if location == region:
                        regional_buckets.append(bucket['Name'])
                except Exception:
                    # Skip buckets we can't access
                    continue
            
            bucket_count = len(regional_buckets)
            
            # Estimate bucket sizes where possible
            total_size_gb = 0
            sized_buckets = 0
            
            for bucket_name in regional_buckets:
                try:
                    # Try to get bucket size from CloudWatch metrics
                    response = cloudwatch.get_metric_statistics(
                        Namespace='AWS/S3',
                        MetricName='BucketSizeBytes',
                        Dimensions=[
                            {'Name': 'BucketName', 'Value': bucket_name},
                            {'Name': 'StorageType', 'Value': 'StandardStorage'}
                        ],
                        StartTime=datetime.utcnow() - timedelta(days=2),
                        EndTime=datetime.utcnow(),
                        Period=86400,
                        Statistics=['Average']
                    )
                    
                    if response['Datapoints']:
                        # Convert bytes to GB
                        size_gb = response['Datapoints'][0]['Average'] / (1024 * 1024 * 1024)
                        total_size_gb += size_gb
                        sized_buckets += 1
                except Exception:
                    # Skip buckets where we can't get metrics
                    continue
            
            # If we have size data for some buckets, use average for the rest
            if sized_buckets > 0:
                avg_size_gb = total_size_gb / sized_buckets
                # Extrapolate for all buckets
                total_size_gb = avg_size_gb * bucket_count
            else:
                # Use default assumption if no size data available
                avg_size_gb = 50  # Assume 50 GB average
                total_size_gb = avg_size_gb * bucket_count
            
            return {
                'count': bucket_count,
                'total_size_gb': round(total_size_gb, 2),
                'avg_size_gb': round(avg_size_gb, 2)
            }
            
        except Exception as e:
            with print_lock:
                print(f"Error counting S3 buckets for account {account_id} in {region}: {e}")
            # Default assumptions:
            # - 10 buckets per account
            # - Average 50 GB per bucket
            return {'count': 10, 'total_size_gb': 500, 'avg_size_gb': 50}
    
    def estimate_ec2_instances(self, account_id, region):
        """
        Count EC2 instances for Snapshot scanning cost estimation.
        
        This method counts EC2 instances in the specified region to estimate
        Snapshot scanning costs. Only Linux instances are counted as those
        are the ones supported by Snapshot.
        
        Args:
            account_id (str): AWS account ID to analyze
            region (str): AWS region to analyze
            
        Returns:
            dict: Dictionary containing instance counts
                {
                    'total': Total number of instances,
                    'linux': Number of Linux instances,
                    'windows': Number of Windows instances,
                    'other': Number of instances with other OS
                }
        """
        if not self.include_snapshot:
            return {'total': 0, 'linux': 0, 'windows': 0, 'other': 0}
            
        session = self._get_account_session(account_id)
        if session is None:
            # Default assumptions:
            # - 20 instances per account
            # - 70% Linux, 25% Windows, 5% Other
            return {'total': 20, 'linux': 14, 'windows': 5, 'other': 1}
        
        try:
            ec2 = session.client('ec2', region_name=region)
            
            # Get all instances
            paginator = ec2.get_paginator('describe_instances')
            
            total_count = 0
            linux_count = 0
            windows_count = 0
            other_count = 0
            
            for page in paginator.paginate(
                Filters=[{'Name': 'instance-state-name', 'Values': ['running', 'stopped']}]
            ):
                for reservation in page['Reservations']:
                    for instance in reservation['Instances']:
                        total_count += 1
                        
                        # Determine OS type
                        platform = instance.get('Platform', '')
                        image_id = instance.get('ImageId', '')
                        
                        if platform and 'windows' in platform.lower():
                            windows_count += 1
                        else:
                            # Try to determine from image ID or tags
                            try:
                                # Check image description
                                image_info = ec2.describe_images(ImageIds=[image_id])
                                description = ''
                                if 'Images' in image_info and image_info['Images']:
                                    description = image_info['Images'][0].get('Description', '').lower()
                                    platform = image_info['Images'][0].get('Platform', '').lower()
                                
                                if 'windows' in description or platform == 'windows':
                                    windows_count += 1
                                elif any(x in description for x in ['linux', 'ubuntu', 'centos', 'rhel', 'amazon', 'debian']):
                                    linux_count += 1
                                else:
                                    # Default to Linux for AWS Linux instances and most others
                                    linux_count += 1
                            except Exception:
                                # Default to Linux when we can't determine
                                linux_count += 1
            
            # Calculate other as remainder
            other_count = total_count - linux_count - windows_count
            
            return {
                'total': total_count,
                'linux': linux_count,
                'windows': windows_count,
                'other': other_count
            }
            
        except Exception as e:
            with print_lock:
                print(f"Error counting EC2 instances for account {account_id} in {region}: {e}")
            # Default assumptions:
            # - 20 instances per account
            # - 70% Linux, 25% Windows, 5% Other
            return {'total': 20, 'linux': 14, 'windows': 5, 'other': 1}
    
    def calculate_costs(self, account_data):
        """
        Calculate estimated CrowdStrike CSPM costs for an account across all regions.
        
        This method:
        1. Gets usage metrics for each region
        2. Applies pricing for each cost component:
           - EventBridge: $1.00 per million events
           - Data egress: Variable by region ($0.09-$0.12 per GB)
           - Lambda: Nominal cost estimate
           - CloudTrail: $0 if using existing trail
           - DSPM: Based on storage and compute
           - Snapshot: Based on EC2 instances
        3. Records total and component costs for reporting
        
        AWS pricing based on official rates as of March 2025.
        CrowdStrike pricing is not included and would be additive.
        
        Assumptions:
        - CloudTrail Events: 1M events/month if no data (conservative estimate)
        - Data Transfer: 5 GB/month if no data
        - S3 Buckets: 10 buckets of 50 GB each if no data
        - EC2 Instances: 20 instances (70% Linux) if no data
        
        Args:
            account_data (dict): Account information with 'id' and 'name' keys
        """
        account_id = account_data['id']
        account_name = account_data['name']
        
        # Get regions enabled for this account
        if self.include_all_regions:
            account_regions = self.get_enabled_regions_for_account(account_id)
            with print_lock:
                print(f"Account {account_name} ({account_id}) has {len(account_regions)} enabled regions")
        else:
            account_regions = self.regions
        
        for region in account_regions:
            with print_lock:
                print(f"Analyzing {account_name} ({account_id}) in region {region}...")
            
            # Gather metrics
            monthly_events = self.estimate_cloudtrail_events(account_id, region)
            monthly_egress_gb = self.estimate_data_transfer(account_id, region)
            
            # Get DSPM metrics if enabled
            s3_data = self.estimate_s3_buckets(account_id, region) if self.include_dspm else {'count': 0, 'total_size_gb': 0}
            
            # Get Snapshot metrics if enabled
            ec2_data = self.estimate_ec2_instances(account_id, region) if self.include_snapshot else {'total': 0, 'linux': 0}
            
            # Calculate costs
            eventbridge_cost = (monthly_events / 1000000) * 1.00  # $1.00 per million events
            
            # Data egress costs vary by region
            egress_rate = 0.09  # Default for most regions (per GB)
            if region.startswith(('ap-', 'me-')):
                egress_rate = 0.11
            elif region.startswith('sa-'):
                egress_rate = 0.12
                
            data_egress_cost = monthly_egress_gb * egress_rate
            
            # Lambda function costs (typically negligible)
            lambda_cost = 0.10  # Estimate for monthly Lambda cost
            
            # CloudTrail costs if not using existing one
            cloudtrail_cost = 0  # Assume using existing CloudTrail
            
            # DSPM costs if enabled
            dspm_cost = 0
            if self.include_dspm and s3_data['count'] > 0:
                # NAT Gateway costs
                nat_hourly_rate = 0.045  # $ per hour
                nat_data_rate = 0.045    # $ per GB processed
                
                # DSPM scanning costs - based on EC2 instance usage and data processed
                dspm_instance_hours = 24  # Estimated hours of c6a.2xlarge usage per scan
                dspm_instance_rate = 0.34  # $ per hour for c6a.2xlarge
                dspm_monthly_scans = 1    # Default is quarterly, but we use monthly for conservative estimate
                
                # Calculate data processing costs
                dspm_instance_cost = dspm_instance_hours * dspm_instance_rate * dspm_monthly_scans
                dspm_data_cost = s3_data['total_size_gb'] * nat_data_rate * dspm_monthly_scans
                dspm_nat_cost = nat_hourly_rate * 24 * dspm_monthly_scans  # Full day per scan
                
                dspm_cost = dspm_instance_cost + dspm_data_cost + dspm_nat_cost
            
            # Snapshot costs if enabled
            snapshot_cost = 0
            if self.include_snapshot and ec2_data['linux'] > 0:
                # Batch compute costs for scanning
                batch_instance_hours = 0.5  # Estimated hours per instance scan
                batch_instance_rate = 0.085  # $ per hour for c5.large
                monthly_snapshot_scans = 4   # Weekly scans by default
                
                # EBS snapshot costs
                avg_instance_storage_gb = 100  # Assumed average instance storage
                ebs_snapshot_rate = 0.05  # $ per GB-month
                
                # Calculate Snapshot costs
                snapshot_compute_cost = ec2_data['linux'] * batch_instance_hours * batch_instance_rate * monthly_snapshot_scans
                snapshot_storage_cost = ec2_data['linux'] * avg_instance_storage_gb * ebs_snapshot_rate * (1/30)  # Daily retention
                
                snapshot_cost = snapshot_compute_cost + snapshot_storage_cost
            
            # Total estimated cost
            total_cost = eventbridge_cost + data_egress_cost + lambda_cost + cloudtrail_cost + dspm_cost + snapshot_cost
            
            result = {
                'Account ID': account_id,
                'Account Name': account_name,
                'Region': region,
                'Monthly CloudTrail Events': int(monthly_events),
                'Monthly Data Egress (GB)': round(monthly_egress_gb, 2),
                'S3 Bucket Count': s3_data['count'],
                'S3 Storage (GB)': round(s3_data['total_size_gb'], 2),
                'EC2 Instance Count': ec2_data['total'],
                'Linux Instance Count': ec2_data['linux'],
                'EventBridge Cost': round(eventbridge_cost, 2),
                'Data Egress Cost': round(data_egress_cost, 2),
                'Lambda Cost': round(lambda_cost, 2),
                'CloudTrail Cost': round(cloudtrail_cost, 2),
                'DSPM Cost': round(dspm_cost, 2),
                'Snapshot Cost': round(snapshot_cost, 2),
                'Total Estimated Cost': round(total_cost, 2)
            }
            
            with print_lock:
                print(f"  CloudTrail Events: {int(monthly_events):,}/month")
                print(f"  Data Egress: {round(monthly_egress_gb, 2)} GB/month")
                
                if self.include_dspm:
                    print(f"  S3 Buckets: {s3_data['count']} ({round(s3_data['total_size_gb'], 2)} GB)")
                    
                if self.include_snapshot:
                    print(f"  Linux Instances: {ec2_data['linux']} of {ec2_data['total']} total")
                    
                print(f"  Estimated Cost: ${round(total_cost, 2)}/month")
            
            self.results.append(result)
    
    def run(self):
        """
        Run the cost estimation process for all accounts in the organization.
        
        This method:
        1. Initiates concurrent analysis of all accounts using ThreadPoolExecutor
        2. Compiles results into a pandas DataFrame
        3. Generates CSV output with detailed cost breakdown
        4. Prints summary reports including:
           - Total estimated cost across all accounts
           - Top 10 accounts by cost
           - Costs by region
           - Business unit summary (if available)
        
        Concurrency is managed to balance performance and API throttling risks.
        """
        start_time = datetime.now()
        print(f"Starting CrowdStrike cost analysis at {start_time}")
        
        # Use threading to analyze multiple accounts concurrently
        with ThreadPoolExecutor(max_workers=20) as executor:
            executor.map(self.calculate_costs, self.accounts)
        
        # Create a pandas DataFrame for analysis
        df = pd.DataFrame(self.results)
        
        # Save results to CSV
        df.to_csv(self.output_file, index=False)
        
        # Generate summary by account
        account_summary = df.groupby(['Account ID', 'Account Name'])['Total Estimated Cost'].sum().reset_index()
        account_summary = account_summary.sort_values('Total Estimated Cost', ascending=False)
        
        # Generate summary by region
        region_summary = df.groupby('Region')['Total Estimated Cost'].sum().reset_index()
        region_summary = region_summary.sort_values('Total Estimated Cost', ascending=False)
        
        # Calculate business unit costs if tags are available
        try:
            # Try to get business unit information from tags
            self._add_business_unit_summary(df)
        except Exception as e:
            print(f"Unable to generate business unit summary: {e}")
        
        # Print summary
        print("\n=== CrowdStrike CSPM Cost Estimation Summary ===")
        print(f"Total Estimated Monthly Cost: ${df['Total Estimated Cost'].sum():.2f}")
        
        print("\nCost by Account (Top 10):")
        for _, row in account_summary.head(10).iterrows():
            print(f"  {row['Account Name']} ({row['Account ID']}): ${row['Total Estimated Cost']:.2f}/month")
        
        print("\nCost by Region:")
        for _, row in region_summary.iterrows():
            print(f"  {row['Region']}: ${row['Total Estimated Cost']:.2f}/month")
        
        if self.include_dspm:
            dspm_total = df['DSPM Cost'].sum()
            print(f"\nDSPM Costs: ${dspm_total:.2f}/month")
            
        if self.include_snapshot:
            snapshot_total = df['Snapshot Cost'].sum()
            print(f"\nSnapshot Costs: ${snapshot_total:.2f}/month")
        
        print(f"\nDetailed results saved to {self.output_file}")
        print(f"Analysis completed in {datetime.now() - start_time}")
    
    def _add_business_unit_summary(self, df):
        """
        Add business unit attribution to cost estimates using AWS Organization tags.
        
        This method:
        1. Retrieves tags for each account in the organization
        2. Identifies business unit tags (various formats supported)
        3. Maps business unit tags to accounts in the results
        4. Generates a business unit summary report
        
        Business unit tags can be in various formats:
        - 'BusinessUnit'
        - 'Business-Unit'
        - 'BU'
        
        Args:
            df (pandas.DataFrame): DataFrame containing the cost analysis results
            
        Returns:
            bool: True if business unit summary was generated, False otherwise
        """
        # This is a placeholder for business unit aggregation logic
        # Example implementation:
        # 1. Get organization tags or account tags
        # 2. Extract BU information 
        # 3. Add BU column to DataFrame
        # 4. Calculate BU-level summaries
        try:
            # Get account IDs
            account_ids = df['Account ID'].unique()
            
            # Get tags for each account
            account_tags = {}
            organizations = self.base_session.client('organizations')
            
            for account_id in account_ids:
                try:
                    response = organizations.list_tags_for_resource(
                        ResourceId=account_id
                    )
                    
                    # Extract business unit tag
                    bu_tag = next((tag for tag in response.get('Tags', []) 
                                if tag['Key'].lower() in ['businessunit', 'business-unit', 'bu']), None)
                    
                    if bu_tag:
                        account_tags[account_id] = bu_tag['Value']
                    else:
                        account_tags[account_id] = 'Untagged'
                except Exception:
                    account_tags[account_id] = 'Untagged'
            
            # Add business unit column to the DataFrame
            df['Business Unit'] = df['Account ID'].map(account_tags)
            
            # Create business unit summary
            bu_summary = df.groupby('Business Unit')['Total Estimated Cost'].sum().reset_index()
            bu_summary = bu_summary.sort_values('Total Estimated Cost', ascending=False)
            
            # Save business unit summary to CSV
            bu_summary.to_csv('crowdstrike_cost_by_business_unit.csv', index=False)
            
            print("\nCost by Business Unit:")
            for _, row in bu_summary.iterrows():
                print(f"  {row['Business Unit']}: ${row['Total Estimated Cost']:.2f}/month")
                
            return True
        except Exception as e:
            print(f"Error generating business unit summary: {e}")
            return False


def main():
    """
    Main function to parse command line arguments and run the cost estimator.
    
    Command line arguments:
    --regions: List of AWS regions to analyze (default: us-east-1)
    --output: Output CSV file name (default: crowdstrike_cost_estimate.csv)
    --all-regions: Analyze all enabled regions for each account
    --include-dspm: Include DSPM cost estimates
    --include-snapshot: Include Snapshot cost estimates
    
    Example usage:
        python crowdstrike_cost_estimator.py --all-regions --include-dspm
    """
    parser = argparse.ArgumentParser(
        description='Estimate CrowdStrike CSPM costs for AWS accounts',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument('--regions', nargs='+', default=None, 
                        help='AWS regions to analyze (e.g., us-east-1 us-west-2)')
    parser.add_argument('--output', default='crowdstrike_cost_estimate.csv',
                        help='Output CSV file name')
    parser.add_argument('--all-regions', action='store_true',
                        help='Analyze all enabled regions for each account')
    parser.add_argument('--include-dspm', action='store_true',
                        help='Include DSPM cost estimates')
    parser.add_argument('--include-snapshot', action='store_true',
                        help='Include Snapshot cost estimates')
    
    args = parser.parse_args()
    
    # Create and run the estimator
    estimator = CrowdStrikeCostEstimator(
        regions=args.regions,
        output_file=args.output,
        include_all_regions=args.all_regions,
        include_dspm=args.include_dspm,
        include_snapshot=args.include_snapshot
    )
    estimator.run()


if __name__ == "__main__":
    main()
