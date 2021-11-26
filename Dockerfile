FROM crystallang/crystal:1.2.2-alpine

RUN apk update && apk install libsqlite3

WORKDIR /build
COPY shard.yml shard.lock .
RUN shards
COPY src/ ./src/
RUN crystal build --release src/bin.cr -o pr-org-stats

CMD ["/bin/pr-org-stats"]
