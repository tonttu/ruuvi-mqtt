FROM alpine:latest

WORKDIR /app
COPY Gemfile* *.rb ./
RUN apk add --no-cache ruby-bundler ruby git \
    && bundle install \
    && apk del git
CMD ["bundle", "exec", "ruby", "ruuvi-mqtt.rb"]
