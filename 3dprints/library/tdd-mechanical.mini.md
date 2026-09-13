# Test-Driven Development (TDD) for Mechanical Engineering

## Core TDD Principles for Design
In hardware and 3D design, TDD shifts from "writing code to pass tests" to **"defining constraints to drive geometry."** The Red-Green-Refactor cycle is adapted as follows:

### Red (Define Constraint)
Before modeling any component, define the engineering requirement. This represents the "failing test." 
*   **Example:** "The bracket must support a 50kg load without exceeding a 2mm deflection" or "The mating hole must have a clearance of 0.5mm."

### Green (Model to Satisfy)
Create the minimum geometry required to satisfy that specific constraint. This is best achieved using parametric modeling (e.g., CadQuery, OpenSCAD) where the "test" is an automated check against the requirement.

### Refactor (Optimize & Generalize)
Once the geometry satisfies the constraint, refine the model for manufacturability, aesthetics, or weight without breaking the original constraint. This involves cleaning up the CAD tree, optimizing fillets, or refining parametric logic.

## STL File Validation Checklist
To ensure a 3D printable or manufacturable file is valid, apply this technical checklist:

| Check Type | Description | Success Criteria |
| :--- | :--- | :--- |
| **Manifoldness** | Ensure the mesh is "watertight." | Every edge must be shared by exactly two faces. No "holes" or "orphan" faces. |
| **Facet Normals** | Verify that all surface normals point outward. | All face normals must consistently point away from the object's center of mass. |
| **Self-Intersection** | Detect if the mesh geometry passes through itself. | Zero volume overlap between non-adjacent triangles. |
| **Degenerate Faces** | Identify zero-area or collinear triangles. | No faces with area $\approx 0$ or vertices that are nearly coincident. |
| **Bounding Box** | Verify dimensions against design specs. | $X, Y, Z$ extents must fall within the specified $[min, max]$ range. |

## Geometric Fitment & Interference Protocol
When designing multi-part assemblies (e.g., a bolt in a hole), use the following protocol to verify fitment:

1. **Bounding Box Analysis:**
   * Calculate the AABB (Axis-Aligned Bounding Box) for all mating components.
   * Verify that the combined bounding box does not exceed the assembly envelope.

2. **Interference Detection:**
   * Perform a Boolean intersection check between Part A and Part B.
   * **Pass:** Intersection volume is zero (or within a negligible "tolerance" threshold).
   * **Fail:** Any non-zero volume indicates a physical collision.

3. **Clearance/Tolerance Calculation:**
   * Calculate the minimum distance ($d_{min}$) between the surface of Part A and Part B.
   * Verify that $d_{min} \geq \text{Required Clearance} + \text{Manufacturing Tolerance}$.

4. **Mating Verification:**
   * For cylindrical fits, verify: $\text{Hole Diameter} - \text{Shaft Diameter} > \text{Tolerance}$.

---
*Note: This book is intended for use by the `coder` and `3d-designer` agents to ensure geometric integrity during parametric modeling.

When working on 3D design or STL generation tasks, the `coder` agent must refer to this book specifically for "Constraint-Driven Geometry" principles to ensure that every geometry change follows a rigorous Red $\rightarrow$ Green $\rightarrow$ Refactor cycle where constraints drive the model.*
