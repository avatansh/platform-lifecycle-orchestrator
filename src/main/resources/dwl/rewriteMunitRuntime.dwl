%dw 2.0
/**
 * Replace the <runtimeVersion>…</runtimeVersion> value (munit-maven-plugin config in an app pom).
 * All occurrences are set to `toRuntime`. No-op if the element is absent.
 *
 * @param pomText     raw app pom.xml text
 * @param toRuntime   target runtime, e.g. "4.9.18"
 */
fun rewriteMunitRuntime(pomText: String, toRuntime: String): String =
    pomText replace /<runtimeVersion>[^<]*<\/runtimeVersion>/ with
        ("<runtimeVersion>" ++ toRuntime ++ "</runtimeVersion>")