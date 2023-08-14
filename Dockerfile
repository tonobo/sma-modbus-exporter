FROM ruby:alpine

COPY . /app
WORKDIR /app
RUN apk add --no-cache ruby-dev build-base curl
RUN gem install bundler && bundle install
CMD ["bundle", "exec", "rackup", "-o", "0.0.0.0", "-p", "5000"]
