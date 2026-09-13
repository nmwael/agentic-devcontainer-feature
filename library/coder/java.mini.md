# Java Reference (Quarkus & Jakarta REST)

## Language Essentials
- **Records**: Use for immutable data carriers.
  ```java
  public record GreetingRequest(String name) {}
  ```
- **Var**: Local variable type inference.
- **Text Blocks**: Multi-line strings using `"""`.
- **Streams/Optionals**: Prefer over null checks and manual loops.
- **Best Practices**: 
  - Favor immutability.
  - Fail fast with clear exceptions.
  - Ensure `equals()` and `hashCode()` are consistent for records/POJOs.

## Jakarta REST (JAX-RS)
- `@Path("/path")`: Define resource URI.
- `@GET`, `@POST`, `@PUT`, `@DELETE`: HTTP methods.
- `@Produces(MediaType.APPLICATION_JSON)`: Response content type.
- `@Consumes(MediaType.APPLICATION_JSON)`: Request content type.
- `@PathParam("name")`: Extract path variables.
- `@QueryParam("key")`: Extract query parameters.
- **JSON bodies**: For POST/PUT, declare the payload as a method parameter; quarkus-rest-jackson maps the JSON body to a record/POJO automatically (no annotation required).
- `Response.ok(...).build()`: Standard response construction.

## Jackson & Serialization
- **Records**: Automatically mapped by `quarkus-rest-jackson`.
- `@JsonProperty("name")`: Explicitly map field names if they differ from JSON keys.
- Use records for request/response bodies to ensure clean, concise code.

## Maven & Quarkus
- **Build**: `./mvnw` (Maven Wrapper) is the standard entry point.
- **Dev Mode**: `mvn quarkus:dev` - Hot reload enabled by default.
- **Package**: `mvn package` or `./mvnw package`.
- **Verify**: `./mvnw verify` for running tests.
- **Dependencies**: Managed via `quarkus-bom` in `<dependencyManagement>`.

## Testing
- `@QuarkusTest`: Annotate test classes to start the managed environment.
- **REST Assured**: Standard tool for testing REST endpoints.
