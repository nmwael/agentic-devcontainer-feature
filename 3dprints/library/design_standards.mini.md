# 3D Design Standards

## Purpose
Guidelines for the `3d-designer` agent to ensure all generated STL files are print-ready, high-quality, and consistent with engineering best practices.

## Geometry Requirements (The "Golden Rules")
- **Manifoldness:** All meshes must be "watertight." Every edge must be shared by exactly two faces. No gaps or non-manifold geometry allowed.
- **Normals:** Facet normals must point outward consistently. Incorrect normals cause slicing failures.
- **Self-Intersection:** The mesh must not have self-intersecting faces.
- **Resolution vs. Accuracy:** Ensure high enough resolution to capture curved features (fillets, radii) without appearing "faceted."

## Design for Manufacturing (DFM) Principles
- **Wall Thickness:** Maintain structural integrity by ensuring walls are thick enough for the target printing technology.
- **Overhangs & Supports:** 
    *   Minimize extreme overhangs; design parts to be self-supporting where possible.
    *   Consider support removal paths for complex geometries.
- **Tolerances & Fits:** Account for clearance, transition, and interference fits. Factor in material shrinkage during the printing process.
- **Infill Strategy:** Use appropriate density/patterns to balance weight vs. strength.

## File Format Workflow (STEP vs. STL)
- **Source of Truth (STEP):** Use STEP files for all design work, parametric modifications, and engineering analysis. They preserve exact curves and surfaces.
- **Final Export (STL):** Only export to STL at the final stage for 3D printing.
- **Export Parameters:**
    *   **Format:** Always use **Binary STL**.
    *   **Chordal Tolerance:** Target ~0.1 mm [0.004 in].
    *   **Angular Tolerance:** Target 1 degree (or a value of 0).
    *   **Minimum Triangle Side Length:** Target 0.1 mm [0.004 in] to avoid "sliver" triangles.
- **File Size Management:** Keep files under 20 MB by balancing resolution and tolerance settings.

## Reference Context
- Primary reference directory: `<WORKSPACE>/3dprints`
- Key components to support: ESP32-C3 Supermini, 0.96" OLED, and various toggle switches.
- Naming Convention: `[Dimension] [Configuration] [Description].stl`

## Reference Books
1. MarkForged: How to create high-quality STL files (https://markforged.com/resources/blog/how-to-create-high-quality-stl-files-for-3d-prints)
2. Hubs Knowledge Base: 3D Printing STL Files Step-by-Step Guide (https://www.hubs.com/knowledge-base/3d-printing-stl-files-step-step-guide/)
3. Purdue Engineering: DETC2016-60407 (https://engineering.purdue.edu/reidlab/assets/DETC2016-60407.pdf)
4. FTC Docs: 3D Printing Booklet (https://ftc-docs-cdn.ftclive.org/booklets/en/3d_printing.pdf)
