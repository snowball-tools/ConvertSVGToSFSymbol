SOURCE_SVG_DIR = ARGV[0]

Dir.foreach(SOURCE_SVG_DIR) do |filename|
    system("ruby SVGToSFSymbol.rb #{SOURCE_SVG_DIR}/" + filename)
end
