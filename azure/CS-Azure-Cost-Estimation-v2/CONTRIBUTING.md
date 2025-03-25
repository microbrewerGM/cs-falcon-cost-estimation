# Contributing Guidelines for CS-Azure-Cost-Estimation-v2

Thank you for your interest in contributing to the CrowdStrike Azure Cost Estimation Tool. To maintain code quality and ensure reliable operation in production environments, please follow these guidelines.

## MANDATORY REQUIREMENTS

### NO DEMO, SHIMS, OR DEV-ONLY CODE

**⚠️ CRITICAL: NEVER CREATE DEMO, SHIMS, DEV MODES, OR OTHER NON-PRODUCTION CODE**

This project is designed for production use in enterprise environments. The following types of code are strictly prohibited:

- **Shims/Compatibility Layers**: Do not create "shim" modules or compatibility layers. All code must directly interact with the actual Azure APIs.
- **Demo Modes**: Do not add code paths for demonstration purposes that would not be used in production.
- **Dev-Only Features**: Do not add features that are only intended for development or testing environments.
- **Mock Implementations**: Do not create mock implementations of services or APIs.

### Why This Rule Exists

- Production reliability requires all code to be fully tested in the actual target environment
- Shims and compatibility layers add unnecessary complexity and potential points of failure
- In an enterprise security context, untested code paths represent potential vulnerabilities
- Maintenance burden increases significantly with special-case code

### Instead, You Should

- Directly use the official Azure PowerShell modules and their documented APIs
- Handle errors and edge cases within the main code path
- Use environment-based configuration for different deployment scenarios
- Document requirements clearly rather than hiding them behind compatibility layers

## Code Style Guidelines

- Follow consistent PowerShell styling as shown in the existing codebase
- Use proper parameter validation in all functions
- Write descriptive comments for complex logic
- Include proper error handling for all external API calls
- Ensure all backticks for line continuation are properly aligned (use Test-BacktickAlignment.ps1)

## Testing Requirements

- All code must pass the existing Test-ScriptSyntax.ps1 checks
- All code must pass the backtick alignment validation
- Functions should be written to be testable with clear inputs and outputs
- Document any special requirements for testing new features

## Documentation

- Update README.md with any new features or significant changes
- Keep configuration documentation current and accurate
- Document any new parameters or configuration options
- Provide examples for non-obvious features

## Submitting Changes

Before submitting changes:
1. Run all tests using the provided test scripts
2. Update documentation as needed
3. Adhere to all guidelines in this document
4. Make sure your code is properly formatted
5. Install the git hooks using the Install-GitHooks.ps1 script

Thank you for helping maintain a high-quality codebase!
