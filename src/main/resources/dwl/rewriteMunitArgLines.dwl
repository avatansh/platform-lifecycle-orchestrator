%dw 2.0
/**
 * dwl::rewriteMunitArgLines — Tier-0 hygiene for Java 17.
 *
 * On Mule 4.9 / Java 17 the embedded MUnit container manages JPMS itself and
 * REJECTS boot-module-layer tweaks (--add-opens / --add-exports / --add-modules)
 * passed as MUnit plugin <argLine>s, failing at test start with
 * "Invalid module tweaking options passed to the JVM running the Mule Runtime".
 *
 * This module strips those offending <argLine> entries — but ONLY inside the
 * MUnit plugin blocks (munit-maven-plugin / munit-extensions-maven-plugin), so a
 * legitimate <argLine> on any other plugin is never touched. An <argLines>
 * wrapper left empty afterwards is removed for tidiness.
 *
 * Pure/text: operates on raw pom text; idempotent (no flags present → unchanged).
 * Unlike version pins, this MUST edit the pom that DECLARES the argLines (a child
 * cannot "override away" an inherited argLine), so it runs on whatever pom carries
 * them — consistent with matrix hygiene rules.
 */

// MUnit plugins whose <argLines> are managed here.
var MUNIT_PLUGIN_ARTIFACTS = ["munit-maven-plugin", "munit-extensions-maven-plugin"]

// True when an <argLine> element's text carries any configured JPMS flag.
fun carriesFlag(argLineXml: String, flags): Boolean =
    !isEmpty((flags default []) filter ((f) -> argLineXml contains (f as String)))

// Strip offending <argLine> elements (and a now-empty <argLines> wrapper) from ONE plugin block.
fun cleanMunitBlock(block: String, flags): String = do {
    var noBadLines = block replace /<argLine>[\s\S]*?<\/argLine>/ with ((m, i) ->
        if (carriesFlag(m[0], flags)) "" else m[0])
    ---
    noBadLines replace /<argLines>\s*<\/argLines>/ with ""
}

/**
 * pomText : raw pom.xml text
 * flags   : array of flag substrings to strip (matrix.removeMunitJpmsFlags)
 * returns : pom text with JPMS argLines removed from MUnit plugin blocks
 */
fun rewriteMunitArgLines(pomText: String, flags): String =
    if (isEmpty(flags default [])) pomText
    else
        // Match each <plugin>…</plugin> block (non-greedy; plugin blocks never nest).
        pomText replace /<plugin>[\s\S]*?<\/plugin>/ with ((m, idx) -> do {
            var block   = m[0]
            var isMunit = !isEmpty(MUNIT_PLUGIN_ARTIFACTS filter ((a) ->
                block contains ("<artifactId>" ++ a ++ "</artifactId>")))
            ---
            if (isMunit) cleanMunitBlock(block, flags) else block
        })
