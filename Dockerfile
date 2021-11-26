FROM crystallang/crystal:1.2.2-alpine

RUN apk update && apk add sqlite-dev

WORKDIR /build
COPY shard.yml shard.lock .
RUN shards
COPY src/ ./src/
RUN crystal build --release src/bin.cr -o /bin/pr-org-stats

WORKDIR $HOME

CMD ["/bin/pr-org-stats"]
