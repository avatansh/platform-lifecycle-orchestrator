package contract;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Test;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;

import javax.xml.parsers.DocumentBuilderFactory;
import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Contract single-source-of-truth guard.
 *
 * <p>The MCP connector requires each tool's {@code <mcp:parameters-schema>} to be a STATIC inline
 * JSON string — it cannot reference an external file or expression. That inline copy can therefore
 * silently drift from the canonical {@code src/main/resources/schema/<tool>.json} files that are the
 * intended single source of truth (shared with RAML on the REST side and the Omni Gateway MCP
 * Schema Validation policy).
 *
 * <p>This test parses the MCP config, extracts each tool's advertised parameters-schema, and asserts
 * it is <em>structurally</em> identical to the canonical file — failing the build on drift. Prose
 * {@code description} fields are ignored (they are advisory, not part of the enforced contract); the
 * comparison covers types, properties, required, enums, items, etc.
 */
class McpSchemaContractTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final File MCP_XML =
            new File("src/main/mule/platform-lifecycle-orchestrator-mcp.xml");
    private static final Path SCHEMA_DIR = Paths.get("src/main/resources/schema");

    @Test
    void advertisedToolSchemasMatchCanonicalFiles() throws Exception {
        Map<String, String> inlineSchemas = extractInlineSchemas();
        assertFalse(inlineSchemas.isEmpty(),
                "No <mcp:parameters-schema> blocks found in " + MCP_XML.getPath()
                        + " — has the MCP config moved?");

        for (Map.Entry<String, String> entry : inlineSchemas.entrySet()) {
            String tool = entry.getKey();
            Path canonical = SCHEMA_DIR.resolve(tool + ".json");

            assertTrue(Files.exists(canonical),
                    "Missing canonical schema file '" + canonical + "' for MCP tool '" + tool
                            + "'. Add it (single source of truth), or the tool name has changed.");

            JsonNode inlineNode = normalize(MAPPER.readTree(entry.getValue()));
            JsonNode fileNode = normalize(MAPPER.readTree(canonical.toFile()));

            assertEquals(fileNode, inlineNode,
                    "MCP tool '" + tool + "' advertised parameters-schema has drifted (structurally) "
                            + "from canonical " + canonical + ". Reconcile them so RAML/REST, the MCP "
                            + "tool, and the Omni Gateway policy stay on one contract.");
        }
    }

    /** tool name -> inline parameters-schema JSON, read from every mcp:tool-listener. */
    private Map<String, String> extractInlineSchemas() throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        Document doc = factory.newDocumentBuilder().parse(MCP_XML);

        NodeList listeners = doc.getElementsByTagNameNS("*", "tool-listener");
        Map<String, String> out = new LinkedHashMap<>();
        for (int i = 0; i < listeners.getLength(); i++) {
            Element listener = (Element) listeners.item(i);
            String name = listener.getAttribute("name");
            NodeList schemas = listener.getElementsByTagNameNS("*", "parameters-schema");
            if (schemas.getLength() > 0) {
                out.put(name, schemas.item(0).getTextContent());
            }
        }
        return out;
    }

    /**
     * Recursively removes non-shape metadata so only the enforced contract is compared:
     * {@code description} (advisory prose) and {@code $schema} (a dialect marker the canonical
     * files carry for tooling/gateway use but the MCP inline blocks omit).
     */
    private JsonNode normalize(JsonNode node) {
        if (node.isObject()) {
            ObjectNode obj = (ObjectNode) node;
            obj.remove("description");
            obj.remove("$schema");
            List<String> fields = new ArrayList<>();
            Iterator<String> it = obj.fieldNames();
            it.forEachRemaining(fields::add);
            for (String f : fields) {
                normalize(obj.get(f));
            }
        } else if (node.isArray()) {
            for (JsonNode child : node) {
                normalize(child);
            }
        }
        return node;
    }
}
