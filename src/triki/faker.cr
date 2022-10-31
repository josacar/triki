require "faker"

class Triki
  abstract class FakerInterface
    module ClassMethods
      abstract def email
      abstract def lorem(number)
      abstract def name
      abstract def first_name
      abstract def last_name
      abstract def street_address
      abstract def city
      abstract def state_abbr
      abstract def zip_code
      abstract def secondary_address
      abstract def phone_number
      abstract def ip_v4_address
      abstract def ip_v6_address
      abstract def url
    end

    macro inherited
      extend ClassMethods
    end
  end

  class Faker < FakerInterface
    def self.email
      ::Faker::Internet.email
    end

    def self.lorem(number)
      ::Faker::Lorem.sentences(number)
    end

    macro define_names(names)
      {% for i in names %}
        def self.{{i}}
          ::Faker::Name.{{i}}
        end
      {% end %}
    end

    define_names [name, first_name, last_name]

    macro define_addresses(addresses)
      {% for i in addresses %}
        def self.{{i}}
          ::Faker::Address.{{i}}
        end
      {% end %}
    end

    define_addresses [street_address, city, state_abbr, zip_code, secondary_address]

    def self.phone_number
      ::Faker::PhoneNumber.phone_number
    end

    def self.company
      ::Faker::Company.name
    end

    macro define_ip_addresses(addresses)
      {% for i in addresses %}
        def self.{{i}}
          ::Faker::Internet.{{i}}
        end
      {% end %}
    end

    define_ip_addresses [ip_v4_address, ip_v6_address]

    def self.url
      ::Faker::Internet.url
    end
  end
end
