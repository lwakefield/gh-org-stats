FROM crystallang/crystal:1.2.2-alpine

WORKDIR /build
COPY shard.yml shard.lock .
COPY src/ ./src/
RUN shards
RUN crystal build --release src/bin.cr -o pr-org-stats

FROM crystallang/crystal:1.2.2-alpine
COPY --from=0 /build/pr-org-stats /bin/pr-org-stats

CMD ["/bin/pr-org-stats"]
