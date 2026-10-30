# Must match the Ruby version in Gemfile / .ruby-version, or bundle install fails (Bundler exit code 18)
FROM ruby:3.4.7

RUN apt-get update && apt-get -y install libpq-dev gcc

WORKDIR /app

# Production image: skip development-only gems (dotenv, listen, byebug).
# Secrets (DB_URL, JWT_SECRET, …) are passed at runtime, e.g. `docker run --env-file .env` — never baked in.
ENV RACK_ENV=production \
    BUNDLE_WITHOUT=development

COPY Gemfile* .

RUN bundle install

COPY . .

EXPOSE 8080

CMD ["puma", "-p", "8080", "-b", "tcp://0.0.0.0"]
