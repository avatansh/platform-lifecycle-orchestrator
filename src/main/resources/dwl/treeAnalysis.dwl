%dw 2.0
/**
 * dwl::treeAnalysis — derives file locations from the GitHub recursive tree and classifies
 * the pom inheritance topology.
 *
 * Pure module: tree, matrix sections and the built chain are passed in explicitly.
 */
import propOf from dwl::pomChain

/**
 * Locates the app pom, mule-artifact.json and CI workflow within the recursive tree and
 * builds the list of all property names the assessment cares about.
 *
 * tree       : the recursive tree object ({ tree: [{path, type,...}], truncated })
 * appPath0   : vars.coords.appPath (nullable; defaults to ".")
 * gating     : matrix.gating   (object of gating rules)
 * connectors : matrix.connectors (array of connector rules)
 */
fun analyzeTree(tree, appPath0, gating, connectors) = do {
    var appPath      = appPath0 default "."
    var nominalPom   = if (appPath == ".") "pom.xml" else (appPath ++ "/pom.xml")
    var treePaths    = tree.tree map $.path
    // Use nominal path when present; otherwise fall back to first blob pom.xml at any depth.
    // Returns null when the repo has no pom.xml at all so the caller can fail with a clear
    // "app pom not found" error instead of fetching a non-existent nominal path.
    var appPomPath   =
        if (treePaths contains nominalPom) nominalPom
        else ((tree.tree filter ((item) ->
                item."type" == "blob" and item.path matches /(?:^|\/)pom\.xml$/
             ))[0].path) default null
    var maPath       = if (appPath == ".") "mule-artifact.json" else (appPath ++ "/mule-artifact.json")
    var maExists     = treePaths contains maPath
    // CI workflow: first .github/workflows/*.yml or *.yaml found in tree
    var ciPath       = ((tree.tree filter ((item) ->
                           item.path matches /\.github\/workflows\/[^\/]+\.ya?ml$/
                       ))[0].path) default null
    // All property names from matrix gating + connectors — needed by ownerOf()
    var allProps     = ((valuesOf(gating) map $.property)
                        ++ (connectors map $.property))
    ---
    {
        appPomPath:          appPomPath,
        muleArtifactExists:  maExists,
        muleArtifactPath:    if (maExists) maPath else null,
        ciWorkflowPath:      ciPath,
        allProps:            allProps
    }
}

/**
 * Classifies the topology from the chain shape and builds a property→ownerPomPath map.
 * chain    : ordered nearest-first list of { path, pom } entries
 * allProps : the property names to map to their owning pom
 */
fun classifyTopology(chain0, allProps) = do {
    // Re-read each pom from its raw text: once the chain is stored in a Mule (application/java)
    // variable, duplicate XML keys collapse (see dwl::assessment rehydrate), which would break
    // dependencyManagement detection and per-property owner resolution below.
    var chain     = (chain0 default []) map ((c) ->
                        { path: c.path, pom: (if (c.pomText?) read((c.pomText as String), "application/xml") else c.pom) })
    var n         = sizeOf(chain)
    var topIsBom  = (chain[-1].pom.project.dependencyManagement?) != null
    var topology  = if (n >= 3 and topIsBom) "BOM_PARENT_APP"
                    else if (n == 2)          "PARENT_APP"
                    else if (n == 1)          "APP_STANDALONE"
                    else                      "MULTI_LEVEL"
    // ownerOf(prop): first POM in the chain (nearest-first) that declares the property.
    // Falls back to the app POM so an edit always has a home (it can be ADDED there).
    fun ownerOf(prop) =
        ((chain filter ((c) -> propOf(c.pom, prop) != null))[0])
            .path default chain[0].path
    ---
    {
      topology: topology,
      appPomPath: chain[0].path,
      ownerByProperty: {
        (allProps map ((p) -> { (p): ownerOf(p) }))
      }
    }
}
