# Maratón container image
FROM node:22-alpine

WORKDIR /app
ENV NODE_ENV=production

# Install production dependencies first so this layer is cached between builds
COPY package.json package-lock.json ./
# Then remove the package managers (npm, npx, corepack, yarn): the app runs with plain
# `node`, and the image scan found HIGH CVEs only inside the npm copy bundled with the
# base image. No package manager in production also means fewer tools for an attacker.
RUN npm ci --omit=dev && npm cache clean --force \
  && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
            /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
            /opt/yarn-v* /usr/local/bin/yarn /usr/local/bin/yarnpkg

COPY . .

# Required by the Wiz exercise: a file named wizexercise.txt containing my name.
# The name is passed in at build time (the CI pipeline sets it with --build-arg),
# and you can verify it in the running pod with:
#   kubectl exec -n maraton deploy/maraton -- cat /app/wizexercise.txt
ARG CANDIDATE_NAME="Patricia Rojas Perez"
RUN echo "${CANDIDATE_NAME}" > /app/wizexercise.txt

# Run as the unprivileged "node" user that ships with the base image
USER node

EXPOSE 3000
CMD ["node", "src/server.js"]
