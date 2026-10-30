FROM ruby:3.4.1


RUN apt-get update && apt-get -y install libpq-dev gcc

WORKDIR /app

COPY Gemfile* .

RUN bundle install

COPY . .

CMD ["puma", "-p", "8080", "-b", "tcp://0.0.0.0"]