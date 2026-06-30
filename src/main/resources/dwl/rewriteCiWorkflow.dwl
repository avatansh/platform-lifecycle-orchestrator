%dw 2.0
/**
 * Bump the Java version in a GitHub Actions workflow using actions/setup-java
 * (e.g. `java-version: '8'` -> `java-version: '17'`). Surrounding quotes/spacing preserved.
 * Other CI mechanisms (strategy matrix `java:`, a `JAVA_VERSION` env var) are intentionally
 * out of scope for the MVP rewrite.
 *
 * @param yamlText        raw workflow YAML text
 * @param toJavaVersion   e.g. "17"
 */
fun rewriteCiWorkflow(yamlText: String, toJavaVersion: String): String =
    yamlText replace /(java-version:[ \t]*["']?)([0-9]+)(["']?)/ with ((m, idx) ->
        m[1] ++ toJavaVersion ++ m[3]
    )