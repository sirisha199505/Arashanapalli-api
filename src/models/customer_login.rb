class App::Models::CustomerLogin < Sequel::Model(:customer_logins)
  # a one-time sign-in code for "My quotations"; only its hash is stored
end
