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

### General Guidelines
- Follow consistent PowerShell styling as shown in the existing codebase
- Use proper parameter validation in all functions
- Write descriptive comments for complex logic
- Include proper error handling for all external API calls

### PowerShell Variable Usage
- **Variable References**: Always use proper PowerShell variable reference syntax:
  - Simple variables can be used directly in strings: `"Value is: $variable"`
  - For properties or methods, use subexpressions: `"Size: $($obj.Size)"`
  - **Critical**: When a variable is followed by a colon or special character, use curly braces: `"Path: ${variable}:subfolder"`
  - Avoid redundant subexpressions for simple variables: Use `$var` not `$($var)`
  - For paths, use Join-Path instead of string concatenation: `Join-Path $dir 'subfolder'`

### Line Continuation
- Ensure all backticks for line continuation are properly aligned
- Continued lines should align with the first parameter or be indented at least 8-10 spaces
- Example of proper backtick alignment:
  ```powershell
  Get-Something -Parameter1 Value1 `
                -Parameter2 Value2 `
                -Parameter3 Value3
  ```

## Testing Requirements

- All code must pass the following validation tests:
  - **Test-PowerShellSyntax.ps1**: Checks for common PowerShell syntax issues, especially variable references
  - **Test-ScriptSyntax.ps1**: Validates general PowerShell syntax
  - **Test-BacktickAlignment.ps1**: Verifies proper backtick alignment

- Run all tests before submitting changes:
  ```powershell
  ./Tests/Test-PowerShellSyntax.ps1 -Path ./YourNewScript.ps1
  ```

- Functions should be written to be testable with clear inputs and outputs
- Document any special requirements for testing new features

## Common PowerShell Runtime Errors and How to Fix Them

### Variable Reference Errors
One of the most common runtime errors in PowerShell is:
```
Variable reference is not valid. ':' was not followed by a valid variable name character
```

This typically occurs in these scenarios:

1. **Path strings with variables**:
   ```powershell
   # INCORRECT - will cause runtime error
   $result = "$folder:subfolder\file.txt"
   
   # CORRECT - use curly braces
   $result = "${folder}:subfolder\file.txt"
   
   # ALTERNATIVE - use subexpression
   $result = "$($folder):subfolder\file.txt"
   
   # BEST PRACTICE - use Join-Path
   $result = Join-Path $folder "subfolder\file.txt"
   ```

2. **When a variable is followed by any non-alphanumeric character** within a string:
   ```powershell
   # INCORRECT - will cause runtime error
   "The value is $value:formatted"
   
   # CORRECT - use curly braces
   "The value is ${value}:formatted"
   ```

3. **String concatenation with +:**
   ```powershell
   # AVOID - error-prone and harder to read
   $path = $dir + "\subfolder\" + $file
   
   # CORRECT - use Join-Path
   $path = Join-Path (Join-Path $dir "subfolder") $file
   ```

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
