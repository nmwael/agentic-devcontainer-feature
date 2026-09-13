# TDD and Testable Code Principles

## Summary
This guide outlines the core principles of Test-Driven Development (TDD), focusing on the Red-Green-Refactor cycle, characteristics of testable code, refactoring strategies, and the use of test doubles to isolate logic.

## The Red-Green-Refactor Cycle
Follow these six steps iteratively to develop robust, tested software:

1. **Red**: Write a failing unit test for a small, specific piece of functionality that does not yet exist. Run the test to confirm it fails.
2. **Green**: Write the minimum amount of production code necessary to make the test pass. Do not worry about elegance at this stage.
3. **Refactor (Internal)**: Clean up the code written in the "Green" step. Improve naming, remove duplication, and ensure it follows best practices while keeping the test passing.
4. **Repeat**: Move to the next requirement or sub-requirement and start again at "Red".

## Testable Code Checklist
To ensure code is easily testable, adhere to these four principles:

- **High Cohesion**: Ensure a class or module has a single, well-defined responsibility.
- **Low Coupling**: Minimize dependencies between different modules. Changes in one area should not necessitate changes in another.
- **Small Units**: Break down complex logic into small, discrete functions or methods that do one thing well.
- **Published Interfaces**: Design code around clear interfaces (APIs) so that the internal implementation can be swapped without affecting consumers.

## Refactoring vs. Feature Addition
Distinguishing between these two is critical for maintaining a stable codebase:

- **Refactoring**: Improving the internal structure of existing code *without* changing its external behavior. Every refactor must be verified by the existing test suite.
- **Feature Addition**: Adding new functionality or behavior. This follows the TDD cycle (Red $\rightarrow$ Green $\rightarrow$ Refactor). New features should never be added without a corresponding failing test first.

## Complex Logic & Test Doubles
When dealing with complex logic that depends on external systems (databases, APIs, file systems), use **Test Doubles** to isolate the unit under test:

- **Mocks/Stubs**: Use these to simulate the behavior of external dependencies.
- **Dependency Injection**: Pass dependencies into your classes via constructors or methods rather than instantiating them internally.
- **Interface Isolation**: Define interfaces for all external services. This allows you to swap a real implementation with a mock during testing, ensuring that tests are fast and deterministic.

## Verification Protocol
- Every unit of work must have a corresponding test.
- If a test is hard to write, the code is likely too complex or poorly decoupled; refactor to improve testability.
