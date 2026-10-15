# Build from the repository root so the shared package is available:
#   docker build -f api/Dockerfile -t capsula-api .
FROM dart:3.13 AS build
WORKDIR /src
COPY packages/capsula_core packages/capsula_core
COPY api/pubspec.yaml api/pubspec.lock api/
WORKDIR /src/api
RUN dart pub get
COPY api/ .
RUN dart compile exe bin/server.dart -o /server

# Minimal runtime image: the compiled binary plus TLS certificates.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /server /app/server
EXPOSE 8787
ENTRYPOINT ["/app/server"]
