# Azure-Specific Modifications

## Modified Files

### server/utils/vectorDbProviders/lance/index.js

**Changes made:**

- **Modified LanceDB URI format** to use Azure Blob Storage protocol instead of local filesystem
- **Modified `connect()` function** to pass Azure Storage SDK credentials
- **Changed storage backend** from Azure Files (SMB) to Azure Blob Storage (object storage)

**Why needed:**

AnythingLLM's default LanceDB implementation doesn't work correctly with Azure Files due to **atomic file operation incompatibility**.

**Technical Details:**
- **Problem:** LanceDB uses a copy-on-write architecture that requires atomic file copy and rename operations with full POSIX filesystem semantics
- **Azure Files limitation:** The SMB protocol used by Azure Files does not support the specific atomic operations LanceDB requires
- **Error encountered:** `LanceError(IO): Unable to copy file from [source] to [destination]: Operation not supported (os error 95)`
- **OS Error 95:** "Operation not supported" - indicates the filesystem doesn't support the required system call
- **Impact:** Documents would parse and embed successfully via OpenAI, but fail when LanceDB attempted to commit the vectors to storage

**Root Cause:**
LanceDB's transactional writes require atomic file operations for ACID compliance. When LanceDB attempts to commit a new version of the vector database, it performs atomic copy operations that the Azure Files SMB mount cannot support, causing vector storage to fail despite successful document processing and embedding.

---

**Lines changed:** 

**Line ~10-12: Modified URI property**
```javascript
// BEFORE (Original):
uri: `${!!process.env.STORAGE_DIR ? `${process.env.STORAGE_DIR}/` : ""}lancedb`,

// AFTER (Modified for Azure Blob):
uri: `az://${process.env.AZURE_CONTAINER_NAME || 'anythingllm-vectors'}/${process.env.AZURE_DATABASE_NAME || 'lancedb'}`,
```
**Purpose:** Changed from local filesystem path to Azure Blob Storage URI format (`az://container/database`)

---

**Line ~15-25: Modified connect() function**
```javascript
// BEFORE (Original):
connect: async function () {
  if (process.env.VECTOR_DB !== "lancedb") 
    throw new Error("LanceDB::Invalid ENV settings");
  
  const client = await lancedb.connect(this.uri);
  return { client };
},

// AFTER (Modified for Azure Blob):
connect: async function () {
  if (process.env.VECTOR_DB !== "lancedb") 
    throw new Error("LanceDB::Invalid ENV settings");
  
  // Add Azure Blob Storage credentials
  const storageOptions = {
    accountName: process.env.AZURE_STORAGE_ACCOUNT_NAME,
    accountKey: process.env.AZURE_STORAGE_ACCOUNT_KEY
  };
  
  const client = await lancedb.connect(this.uri, { storageOptions });
  return { client };
},
```
**Purpose:** Pass Azure Storage SDK credentials to enable authentication with Azure Blob Storage backend

---

**Line ~13: Added name property (housekeeping)**
```javascript
name: "LanceDb",
```
**Purpose:** Ensure proper object structure (was in original but may have been accidentally removed during modification)

---

**Environment Variables Required:**

These new environment variables must be set in the container:
```bash
AZURE_STORAGE_ACCOUNT_NAME=anythingllmtrpvectors
AZURE_STORAGE_ACCOUNT_KEY=[storage-account-key]
AZURE_CONTAINER_NAME=anythingllm-vectors
AZURE_DATABASE_NAME=lancedb
```

---

**Upstream issue:** 

- **Status:** Not yet reported to upstream maintainers
- **GitHub Issue:** Should be reported as: "LanceDB provider incompatible with Azure Files SMB mounts - requires Azure Blob Storage support"
- **Potential upstream solution:** Add Azure Blob Storage as a supported backend option with configuration flag
- **Alternative:** Document Azure Files incompatibility in deployment guide

**Recommendation:** Consider submitting a Pull Request to upstream with Azure Blob Storage support as an optional backend, as this benefits all Azure users of AnythingLLM.

---

## Testing

**Verified working on:**
- **Platform:** Azure Container Instances (2 vCPU, 4GB RAM)
- **Storage:** Azure Blob Storage (Standard LRS, Hot tier)
- **Region:** Canada Central
- **Vector embeddings:** Successfully tested with up to 29 chunks (~50-100 page documents)
- **Operations tested:**
  - ✅ Document upload and parsing
  - ✅ OpenAI embedding generation
  - ✅ Vector storage to Blob Storage
  - ✅ Vector retrieval for semantic search
  - ✅ Multi-document queries with citations
  - ✅ Container restart persistence

**Performance:**
- Embedding generation: ~10-30 seconds per 10-page document
- Query response time: 2-5 seconds (includes OpenAI API call)
- No observable performance degradation vs. local filesystem

**Known Limitations:**
- Requires internet connectivity to Azure Blob Storage (not an issue for ACI)
- Additional environment variables needed vs. default configuration
- Blob Storage costs apply (minimal: ~$1-2/month for typical usage)

---

## Update Strategy

**When pulling upstream updates:**

1. **Sync main branch with upstream:**
   ```bash
   git checkout main
   git fetch upstream
   git merge upstream/main
   git push origin main
   ```

2. **Rebase or merge azure-custom branch:**
   ```bash
   git checkout azure-custom
   git rebase main  # Or: git merge main
   ```

3. **Review conflicts in index.js carefully:**
   - Focus on the `uri` property and `connect()` function
   - Ensure Azure Blob Storage modifications are preserved
   - Check if upstream added new LanceDB features that need Azure compatibility

4. **Test locally before deploying:**
   ```bash
   # Build test image
   docker build -t anythingllm-azure:test .
   
   # Run with Azure credentials
   docker run -p 3001:3001 \
     -e VECTOR_DB=lancedb \
     -e AZURE_STORAGE_ACCOUNT_NAME=[storageaccountname] \
     -e AZURE_STORAGE_ACCOUNT_KEY=[key] \
     -e AZURE_CONTAINER_NAME=[containername]] \
     -e AZURE_DATABASE_NAME=lancedb \
     anythingllm-azure:test
   
   # Test document upload and search
   ```

5. **Document any new conflicts:**
   - Update this file with new line numbers if structure changes
   - Note any new LanceDB features that may need Azure Blob compatibility
   - Consider if changes affect other vector database providers

6. **Deploy to production:**
   - Tag with version: `v1.1.0`, `v1.2.0`, etc.
   - Push to ACR
   - Update ARM template parameters if needed
   - Deploy and verify

---

## Maintenance Notes

**Monitoring for upstream changes:**
- Subscribe to AnythingLLM releases: https://github.com/Mintplex-Labs/anything-llm/releases
- Watch for LanceDB version updates in `package.json`
- Monitor for issues related to Azure deployments

**If LanceDB library updates:**
- Check LanceDB changelog for Azure Blob Storage improvements
- Test compatibility with new LanceDB versions
- May be able to simplify our modifications if native support added

**Future possibilities:**
- Upstream may add official Azure Blob Storage support
- Could switch to managed LanceDB cloud (if available)
- Monitor for alternative vector databases with better Azure compatibility

---

**Last Updated:** December 30, 2025  