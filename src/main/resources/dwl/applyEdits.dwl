%dw 2.0
/**
 * dwl::applyEdits — applies a file's approved edit list to its raw (base64) GitHub
 * content, running each rewrite module in the same fixed order used previously by
 * the inline pf-apply-transforms transform.
 *
 * Pure module: base64 content + edit list are passed in explicitly.
 */
import rewritePomProperties  from dwl::rewritePomProperties
import rewriteDepVersions    from dwl::rewriteDepVersions
import rewritePluginVersions from dwl::rewritePluginVersions
import rewriteMunitRuntime   from dwl::rewriteMunitRuntime
import rewriteMuleArtifact   from dwl::rewriteMuleArtifact
import rewriteCiWorkflow     from dwl::rewriteCiWorkflow
import rewriteMunitArgLines  from dwl::rewriteMunitArgLines
import rewritePomVersion     from dwl::rewritePomVersion
import fromBase64 from dw::core::Binaries

/**
 * base64Content : raw base64 file content from the GitHub Contents API
 * edits         : the edit list for this file (kinds: depVersion, pluginVersion,
 *                 pomProperty, munitRuntimeVersion, muleArtifactJson, ciWorkflow,
 *                 munitArgLines, pomVersion)
 * returns       : the rewritten file text
 *
 * Inline dependency + plugin <version> rewrites run first, then property rewrites
 * (independent regions), matching the original ordering.
 */
fun applyEdits(base64Content, edits) = do {
    var rawText   = (fromBase64((base64Content default "") replace /[\r\n\t ]/ with "")) as String {encoding: "UTF-8"}
    var depEdits  = edits filter ((e) -> e.kind == "depVersion")
    var stepA     = if (!isEmpty(depEdits)) rewriteDepVersions(rawText, depEdits) else rawText
    var plgEdits  = edits filter ((e) -> e.kind == "pluginVersion")
    var step0     = if (!isEmpty(plgEdits)) rewritePluginVersions(stepA, plgEdits) else stepA
    var propEdits = edits filter ((e) -> e.kind == "pomProperty")
    var step1     = if (!isEmpty(propEdits)) rewritePomProperties(step0, propEdits) else step0
    var munitEdit = (edits filter ((e) -> e.kind == "munitRuntimeVersion"))[0]
    var step2     = if (munitEdit != null) rewriteMunitRuntime(step1, munitEdit.to as String) else step1
    var maEdit    = (edits filter ((e) -> e.kind == "muleArtifactJson"))[0]
    var step3     = if (maEdit != null)
                        rewriteMuleArtifact(step2, maEdit.to.minMuleVersion as String, maEdit.to.javaSpecificationVersions)
                    else step2
    var ciEdit    = (edits filter ((e) -> e.kind == "ciWorkflow"))[0]
    var step4     = if (ciEdit != null) rewriteCiWorkflow(step3, ciEdit.to as String) else step3
    // Tier-0 hygiene: strip JPMS argLines from MUnit plugin blocks so MUnit runs on Java 17.
    var argEdit   = (edits filter ((e) -> e.kind == "munitArgLines"))[0]
    var step5     = if (argEdit != null) rewriteMunitArgLines(step4, argEdit.flags) else step4
    // Minor-bump the app module's own <version> (only ever emitted for the app pom, and only
    // when the upgrade actually changes something — see dwl::assessment).
    var verEdit   = (edits filter ((e) -> e.kind == "pomVersion"))[0]
    var step6     = if (verEdit != null)
                        rewritePomVersion(step5, (verEdit.artifactId default "") as String, (verEdit.to default "") as String)
                    else step5
    ---
    step6
}
