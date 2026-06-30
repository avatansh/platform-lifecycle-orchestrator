%dw 2.0
/**
 * Surgically rewrite Maven <property> VALUES in a pom.xml without reformatting the file.
 * Only elements whose tag name appears in `edits` are changed; every other byte
 * (comments, ordering, indentation, unrelated elements) is preserved untouched.
 * Works on ANY pom in the chain (app / parent / bom) — the caller passes the edits
 * that belong to that specific file.
 *
 * @param pomText  raw pom.xml text (already base64-decoded)
 * @param edits    array of objects shaped { property: String, to: String, ... };
 *                 extra fields (file, from, kind, change) are ignored
 * @return         rewritten pom.xml text
 */
fun rewritePomProperties(pomText: String, edits: Array): String = do {
    // tag name -> new value
    var editMap = edits reduce ((e, acc = {}) -> acc ++ { (e.property): (e.to as String) })
    ---
    // Match <tag>value</tag> where the close tag matches the open tag (backreference \1).
    // Only rewrite when the tag is one we were asked to change; otherwise emit the match as-is.
    pomText replace /<([A-Za-z0-9_.-]+)>([^<]*)<\/\1>/ with ((m, idx) ->
        if (editMap[m[1]] != null)
            "<" ++ m[1] ++ ">" ++ editMap[m[1]] ++ "</" ++ m[1] ++ ">"
        else
            m[0]
    )
}