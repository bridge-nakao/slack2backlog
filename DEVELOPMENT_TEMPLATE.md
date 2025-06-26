# Development Template - 23-Step Development Flow

This is a generic development template based on the Claude Code development methodology. Replace `[PROJECT_NAME]` with your actual project name throughout this document.

## 📋 Standard Development Flow (Revised - 23 Steps)

### Phase 1: Specification Review
1. **Specification Proposal Receipt** - Receive requirements for desired features
   - 📊 **Projects Update**: Add new task to "Backlog", move to "Specification Review"
2. **Specification Review & Proposal** - Conduct technical review and propose detailed specifications
3. **Specification Review** - Review proposed specifications
4. **Specification Revision** - Address feedback and concerns
5. **Specification Finalization** - Repeat steps 2-4 until no revisions needed
   - 📊 **Projects Update**: Move from "Specification Review" to "In Development"

### Phase 2: Implementation
6. **Issue Registration** - Register finalized specifications as GitHub Issue
   - 📊 **Projects Update**: Issue automatically added to Projects
7. **Git Worktree Creation** - Prepare independent development environment
   ```bash
   git worktree add ../[PROJECT_NAME]-feature-name feature/feature-name
   cd ../[PROJECT_NAME]-feature-name
   npm install  # or your package manager
   ```
8. **Program Implementation** - Implement the feature
9. **Test Program Creation** - Create tests using actual source files (no class redefinition)

### Phase 3: Quality Assurance
10. **New Feature Test Execution** - Run created tests
    - 📊 **Projects Update**: Move from "In Development" to "Testing"
    - If failed → Return to step 8 (program modification)
11. **Existing Test Verification** - Run all existing tests after new feature tests pass
    - If failed → Return to step 8 (program modification)
12. **Coverage Measurement** - Measure coverage after all tests pass
    - 📊 **Projects Update**: Update custom field "Test Coverage"
13. **Coverage Improvement** - Aim for 80% or higher coverage
    - If insufficient → Return to step 9 (add tests)

### Phase 4: Verification
14. **Manual Test Items Preparation** - Create manual verification checklist (including regression testing)
15. **Manual Test Execution** - Verify functionality
    - If failed → Return to step 4 (specification review) or step 8 (implementation fix)
    - **Manual Test Method**: Present test items one by one, user responds with "OK" or "NG"
    - **Manual Test Details**: Document procedures and expected results in `MANUAL_TEST_GUIDE.md`

### Phase 5: Completion
16. **Documentation Update** - Update README.md and project documentation
17. **Project Documentation Review** - Add improvements based on development experience
    - Newly discovered best practices
    - Problems encountered and solutions
    - Test strategy updates
    - Worktree operation improvements
18. **Commit Creation** - Commit changes
19. **Pull Request Creation** - Create PR for review
    - 📊 **Projects Update**: PR automatically added to Projects, displayed in "In review" view
20. **Code Review** - Conduct code review on GitHub
    - Address review comments
    - If modifications needed, return to step 8
    - After approval, ready for merge
21. **PR Merge** - Merge to main branch after review completion
    - 📊 **Projects Update**: Move from "In review" to "Done"
22. **Cleanup Unnecessary Files** - Remove unused files
23. **Cycle Continuation** - Return to step 1 for new requirements

### 📝 Important Principles
- **Use Actual Files**: Tests must always use actual source files
- **100% Success Rate**: All tests must pass before proceeding
- **80% Coverage Target**: Aim to achieve this for all files
- **Prevent Regression**: Always verify new features don't break existing functionality

**⚠️ This flow must be followed completely. Any missing step results in incomplete implementation.**

### 🔍 Code Review Guidelines
- **Review Points**:
  - Code readability and maintainability
  - Consistency with existing code
  - Adequate test coverage
  - Security concerns
  - Performance impact
- **Review Process**:
  - Request review when creating PR
  - Respond promptly to comments and modification requests
  - Merge after review approval

### 🚨 Test Completion Requirements
- **Do not proceed to coverage measurement if all tests are not 100% complete**
- If any test fails, fix all tests before proceeding
- Test completion = All tests in the test suite pass successfully

## 📊 GitHub Projects Integration Policy

### Project Overview
- **Project Name**: [PROJECT_NAME] Development Roadmap
- **Template**: Feature release
- **Views**: Prioritized backlog, Status board, Roadmap, Bugs, In review, My items

### Custom Fields Configuration
Manage the 23-step development flow efficiently with these custom fields:
- **Development Phase**: 1-5 (Specification/Implementation/QA/Verification/Completion)
- **Current Step**: Track progress with numbers 1-23
- **Worktree Name**: [PROJECT_NAME]-feature-name (workspace identification)
- **Test Coverage**: XX.XX% (quality metric)

### Status (Column) Structure
Visualize progress with 6 detailed stages:
```
📋 Backlog → 🔍 Specification Review → 💻 In Development → 🧪 Testing → 👀 In review → ✅ Done
```

### Automation Rules
Minimize operational load with minimal automation:
- **Issue/PR Creation**: Automatically placed in "Backlog"
- **Other Movements**: Manual updates based on progress reports

### Operation Rules

#### Issue/PR Management
- **Issue Creation (Step 6)**: Register finalized specifications in GitHub Issue
- **PR Creation (Step 19)**: Include implementation details, test results, and coverage

#### Status Update Timing
1. **Backlog → Specification Review**: When specification review begins (Step 1)
2. **Specification Review → In Development**: When specifications are finalized (Step 5)
3. **In Development → Testing**: When testing begins (Step 10)
4. **Testing → In review**: When PR is created (Step 19)
5. **In review → Done**: When PR merge is complete (Step 21)

#### Manual Test Recording Method
Create a checklist in the PR in this format:
```markdown
## Manual Test Results
- [ ] Test 1: Basic functionality - OK
- [ ] Test 2: Feature X functionality - OK
- [ ] Test 3: UI display - OK
...
- [x] All manual tests completed (10/10 OK)
```

### View Usage
- **Prioritized backlog**: Task management based on priority
- **Status board**: Overview of current progress (main view)
- **Roadmap**: Long-term development plan visualization
- **Bugs**: Bug-specific tracking and management
- **In review**: PR/Issue management under review
- **My items**: Tasks assigned to individuals

### Best Practices
1. **Regular Updates**: Always update status when completing each phase
2. **Detailed Recording**: Use custom fields to record progress in detail
3. **Ensure Transparency**: Visualize all work in Projects
4. **Weekly Review**: Review priorities in Prioritized backlog

### Automation Scripts
Prepare scripts to simplify initial project setup and operations:

#### Initial Setup Script
```bash
# Automatic custom field configuration
./scripts/setup-github-project.sh
```

#### Helper Functions
```bash
# Display project information
source scripts/github-project-helpers.sh && show_project_info

# Add Issue to project
source scripts/github-project-helpers.sh && add_issue_to_project 1

# Update custom field
source scripts/github-project-helpers.sh && update_custom_field ITEM_ID "Test Coverage" 84.89
```

## 🚀 Release Process

### Pre-Release Checklist
- [ ] All tests passing (100%)
- [ ] Coverage 80% or higher achieved
- [ ] Security audit completed
- [ ] Performance tests passed
- [ ] Version updated in configuration files
- [ ] CHANGELOG.md updated
- [ ] README.md updated (as needed)
- [ ] Manual testing completed (all features)
- [ ] Memory leak check completed
- [ ] Platform-specific compliance verified

### Version Management Strategy

#### Semantic Versioning
- **Format**: MAJOR.MINOR.PATCH (e.g., 1.2.3)
- **MAJOR**: Breaking changes (no backward compatibility)
- **MINOR**: Feature additions (backward compatible)
- **PATCH**: Bug fixes

#### Version Update Procedure
```bash
# Update version in configuration files
# Update to "version": "1.2.3"

# Create release tag
git tag -a v1.2.3 -m "Release version 1.2.3: Feature description"
git push origin v1.2.3

# CHANGELOG.md update example
## [1.2.3] - 2025-01-19
### Added
- New feature X
### Fixed
- Bug fix Y
```

### Build and Distribution Process

1. **Create Build Package**
   ```bash
   # Create ZIP excluding unnecessary files
   zip -r [project-name]-v1.2.3.zip . \
     -x "*.git*" \
     -x "node_modules/*" \
     -x "tests/*" \
     -x "coverage/*" \
     -x "*.md" \
     -x "package*.json" \
     -x "*config.js" \
     -x "scripts/*"
   ```

2. **Prepare Required Assets**
   - Screenshots (as per platform requirements)
   - Promotional images
   - Icons
   - Descriptions (multiple languages if needed)

3. **Platform-Specific Requirements**
   - Category selection
   - Language support
   - Target audience

4. **Privacy Policy**
   - Data collection disclosure
   - Permission explanations

5. **Submission Process**
   - Review period expectations
   - Rejection response preparation

## ⚡ Performance Standards

### Required Metrics
- **Processing Time**: Define acceptable limits for main operations
- **Memory Usage**: Set maximum memory consumption
- **Startup Time**: Define acceptable initialization time
- **Response Time**: Set UI responsiveness standards

### Performance Test Implementation
```javascript
// Example performance test
describe('Performance Tests', () => {
  test('Large data processing performance', async () => {
    const largeDataSet = generateTestData(1000);
    const startTime = performance.now();
    
    await processData(largeDataSet);
    
    const endTime = performance.now();
    expect(endTime - startTime).toBeLessThan(1000); // 1 second limit
  });
});
```

## 📝 Template Usage Instructions

1. **Replace Placeholders**: 
   - Replace all instances of `[PROJECT_NAME]` with your actual project name
   - Replace `[project-name]` with your project name in lowercase/kebab-case
   - Adjust file extensions and build processes according to your technology stack

2. **Customize Sections**:
   - Modify the worktree creation commands based on your package manager
   - Adjust test coverage targets based on your project requirements
   - Update performance standards specific to your application

3. **Script Adaptation**:
   - The referenced scripts in `./scripts/` should be created based on your project needs
   - Automation scripts should be adapted to your CI/CD pipeline

4. **GitHub Projects Setup**:
   - Create a new project using the "Feature release" template
   - Add the custom fields as specified
   - Configure automation rules according to your workflow

This template provides a comprehensive development methodology that ensures quality, consistency, and efficient project management. Adapt it to your specific needs while maintaining the core 23-step process.