FROM mintplexlabs/anythingllm:latest

# Just copy our modified LanceDB file
COPY server/utils/vectorDbProviders/lance/index.js /app/server/utils/vectorDbProviders/lance/index.js