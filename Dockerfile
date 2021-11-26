FROM crystallang/crystal:1.2.2-alpine

RUN apk update && apk add sqlite-dev

WORKDIR /build
COPY shard.yml shard.lock .
RUN shards
COPY src/ ./src/
RUN crystal build src/bin.cr -o /bin/gh-org-stats

WORKDIR $HOME

CMD ["/bin/gh-org-stats"]
