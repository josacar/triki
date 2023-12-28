class Triki
  abstract struct Base
    abstract def parse(obfuscator, config, input_io, output_io)
  end
end
