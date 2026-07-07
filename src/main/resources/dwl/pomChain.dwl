%dw 2.0
/**
 * dwl::pomChain — helpers for walking a Maven pom inheritance chain (app → parent →
 * grandparent/BOM) during assessment.
 *
 * Pure module: all inputs (base64 content, paths, tree path list, already-built chain)
 * are passed in explicitly — no reliance on Mule payload/vars/p().
 */
import fromBase64 from dw::core::Binaries

/** Drops the last element of a path-segment array (parent directory step). */
fun removeLastSeg(arr: Array): Array =
    if (sizeOf(arr) <= 1) [] else arr[0 to (sizeOf(arr) - 2)]

/**
 * Resolves a relative parent path against the directory of the current pom, collapsing
 * "." and ".." segments. e.g. normalizePath("a/b/pom.xml", "../pom.xml") -> "a/pom.xml".
 */
fun normalizePath(currentPomPath: String, relPath: String): String = do {
    var dir      = if (currentPomPath contains "/")
                       currentPomPath[0 to ((currentPomPath lastIndexOf "/") - 1)]
                   else ""
    var combined = if (dir == "") relPath else (dir ++ "/" ++ relPath)
    var parts    = (combined splitBy "/") filter ($ != "" and $ != ".")
    --- (parts reduce ((seg, acc = []) ->
            if (seg == ".." and !isEmpty(acc)) removeLastSeg(acc)
            else acc ++ [seg]
        )) joinBy "/"
}

/** Base64-decodes GitHub Contents-API file content to a UTF-8 string. */
fun decodePom(base64Content): String =
    (fromBase64((base64Content) replace /[\r\n\t ]/ with "")) as String {encoding: "UTF-8"}

/**
 * Reads a Maven <properties> value by NAME, matching the key as a plain String so
 * dotted names (e.g. app.runtime.semver) and XML namespace Key types resolve reliably.
 */
fun propOf(pom, prop) = do {
    var pairs = (pom.project.properties default {}) pluck ((pv, pk) -> { name: (pk as String), value: pv })
    --- (pairs filter ($.name == prop))[0].value default null
}

/**
 * Resolves the next parent pom path IN THIS REPO for a parsed pom, honouring Maven's
 * default (<parent> with no <relativePath> ⇒ ../pom.xml) and directory-form relativePath
 * (append /pom.xml). Returns null when there is no parent or the parent lives outside the
 * repo tree (external/Exchange parent stops the chain).
 */
fun nextParentPath(parsedPom, currentPomPath: String, treePaths): Any = do {
    var parentEl      = parsedPom.project.parent
    var rawRel        = parentEl.relativePath default null
    var relForResolve =
        if (parentEl == null) null
        else if (rawRel == null or (rawRel as String) == "") "../pom.xml"
        else (rawRel as String)
    var resolved      = if (relForResolve == null) null
                        else normalizePath(currentPomPath, relForResolve)
    var resolvedFile  = if (resolved == null) null
                        else if (resolved matches /.*pom\.xml$/) resolved
                        else (resolved ++ "/pom.xml")
    ---
    if (resolvedFile != null and (treePaths contains resolvedFile)) resolvedFile
    else null
}

/**
 * Initialises the chain from the app pom.
 * base64Content : app pom.xml content (base64, from Contents API)
 * appPomPath    : the app pom path
 * treePaths     : list of every path in the repo tree
 * returns       : { appPomText, chain: [{path, pom}], nextParentPath }
 */
fun initChain(base64Content, appPomPath: String, treePaths) = do {
    var rawContent = decodePom(base64Content)
    var parsedPom  = read(rawContent, "application/xml")
    ---
    {
        appPomText:     rawContent,
        chain:          [{ path: appPomPath, pom: parsedPom }],
        nextParentPath: nextParentPath(parsedPom, appPomPath, treePaths)
    }
}

/**
 * Appends the next parent pom to an existing chain.
 * base64Content : parent pom.xml content (base64)
 * parentPath    : the path of the parent pom being appended
 * chain         : the chain so far
 * treePaths     : list of every path in the repo tree
 * returns       : { chain, nextParentPath }
 */
fun appendParent(base64Content, parentPath: String, chain, treePaths) = do {
    var rawContent = decodePom(base64Content)
    var parsedPom  = read(rawContent, "application/xml")
    ---
    {
        chain:          chain ++ [{ path: parentPath, pom: parsedPom }],
        nextParentPath: nextParentPath(parsedPom, parentPath, treePaths)
    }
}
