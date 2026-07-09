%dw 2.0
/**
 * Surgically rewrite Maven <property> VALUES in a pom.xml without reformatting the file.
 * Only elements whose tag name appears in `edits` are changed; every other byte
 * (comments, ordering, indentation, unrelated elements) is preserved untouched.
 * Works on ANY pom in the chain (app / parent / bom) — the caller passes the edits
 * that belong to that specific file.
 *
 * Add-if-absent: an edit flagged { addIfAbsent: true } whose property tag is NOT already
 * present is INSERTED into the pom's <properties> block (or a new block before </project>
 * when none exists). This backs the appOverride strategy, where a property inherited from a
 * parent/BOM is overridden by adding it to the app's own pom. Edits WITHOUT the flag keep the
 * original replace-only, no-op-when-absent contract used by the legacy inPlace strategy.
 *
 * @param pomText  raw pom.xml text (already base64-decoded)
 * @param edits    array of objects shaped { property: String, to: String, addIfAbsent?: Boolean, ... };
 *                 extra fields (file, from, kind, change) are ignored
 * @return         rewritten pom.xml text
 */
import substringBefore, substringAfter from dw::core::Strings

fun rewritePomProperties(pomText: String, edits: Array): String = do {
    // tag name -> new value
    var editMap = edits reduce ((e, acc = {}) -> acc ++ { (e.property): (e.to as String) })
    // 1) Replace target property tags that are already present, preserving every other byte.
    var replaced = pomText replace /<([A-Za-z0-9_.-]+)>([^<]*)<\/\1>/ with ((m, idx) ->
        if (editMap[m[1]] != null)
            "<" ++ m[1] ++ ">" ++ editMap[m[1]] ++ "</" ++ m[1] ++ ">"
        else
            m[0])
    // 2) Add-if-absent: only edits flagged addIfAbsent whose tag was NOT present in the original.
    var additions = edits
        filter ((e) -> (e.addIfAbsent default false) and !(pomText contains ("<" ++ (e.property as String) ++ ">")))
        map ((e) -> "    <" ++ (e.property as String) ++ ">" ++ (e.to as String) ++ "</" ++ (e.property as String) ++ ">")
    ---
    if (isEmpty(additions))
        replaced
    else if (replaced contains "</properties>")
        // Insert before the FIRST closing </properties>.
        ((replaced substringBefore "</properties>") ++ (additions joinBy "\n") ++ "\n  </properties>"
         ++ (replaced substringAfter "</properties>"))
    else
        // No <properties> block — create one just before </project>.
        ((replaced substringBefore "</project>")
         ++ "  <properties>\n" ++ (additions joinBy "\n") ++ "\n  </properties>\n"
         ++ "</project>" ++ (replaced substringAfter "</project>"))
}