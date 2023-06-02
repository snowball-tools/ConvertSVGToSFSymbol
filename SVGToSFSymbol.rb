# article this script is based off https://techlife.cookpad.com/entry/2021/01/05/custom-symbols-en
require "nokogiri" # Load the XML library we are going to use.

# Path to file exported from the SF Symbols app
TEMPLATE_PATH = "template.svg"
# Path to one of the SVGs provided by the designers
SOURCE_SVG_PATH = ARGV[0]
# Path to the SVG we are generating
DESTINATION_SVG_PATH = ARGV[0]

# Expected icon size
ICON_WIDTH = 32
ICON_HEIGHT = 32
# Additional scaling to have a size closer to Apple's provided SF Symbols
# (I just tried different values and that looked pretty close)
ADDITIONAL_SCALING = 1.7
# Width of #left-margin and #right-margin inside the SVG
MARGIN_LINE_WIDTH = 0.5
# Additional white space added on each side
ADDITIONAL_HORIZONTAL_MARGIN = 4

# Load the template.
template_svg = File.open(TEMPLATE_PATH) do |f|
  # To generate a better looking SVG, ignore whitespaces.
  Nokogiri::XML(f) { |config| config.noblanks }
end

def get_guide_value(template_svg, axis, xml_id)
  guide_node = template_svg.at_css("##{xml_id}")
  raise "invalid axis" unless %i{x y}.include?(axis)
  val1 = guide_node["#{axis}1"]
  val2 = guide_node["#{axis}2"]
  if val1 == nil || val1 != val2
    raise "invalid #{xml_id} guide"
  end
  val1.to_f # Convert the value from string to float.
end

# Get the x1 (should be the same as x2) of the #left-margin node.
original_left_margin = get_guide_value(template_svg, :x, "left-margin")
# Get the x1 (should be the same as x2) of the #right-margin node.
original_right_margin = get_guide_value(template_svg, :x, "right-margin")
# Get the y1 (should be the same as y2) of the #Baseline-M node.
baseline_y = get_guide_value(template_svg, :y, "Baseline-M")
# Get the y1 (should be the same as y2) of the #Capline-M node.
capline_y = get_guide_value(template_svg, :y, "Capline-M")

# Load the SVG icon.
icon_svg = File.open(SOURCE_SVG_PATH) do |f|
    # To generate a better looking SVG, ignore whitespaces.
  Nokogiri::XML(f) { |config| config.noblanks }
end

# The SVGs provided by designers had a fixed size of 64x64, so all the calculations below are based on this.
# If we get an unexpected size, the program ends in error.
# The SVG specs allows to specify width and height in not only numbers, but also percents, so handling a wider range of SVG files would be more complicated.
if icon_svg.root["width"] != ICON_WIDTH.to_s ||
  icon_svg.root["height"] != ICON_HEIGHT.to_s ||
  icon_svg.root["viewBox"] != "0 0 #{ICON_WIDTH} #{ICON_HEIGHT}"
  raise "expected icon size of #{SOURCE_SVG_PATH} to be (#{ICON_WIDTH}, #{ICON_HEIGHT})"
end

scale = ((baseline_y - capline_y).abs / ICON_HEIGHT) * ADDITIONAL_SCALING
horizontal_center = (original_left_margin + original_right_margin) / 2

scaled_width = ICON_WIDTH * scale
scaled_height = ICON_HEIGHT * scale

# If you use the template's margins as-is, the generated symbol's width will depend on the template chosen.
# To not have to care about the template, we move the margin based on the computed symbol size.
horizontal_margin_to_center = scaled_width / 2 + MARGIN_LINE_WIDTH + ADDITIONAL_HORIZONTAL_MARGIN
adjusted_left_margin = horizontal_center - horizontal_margin_to_center
adjusted_right_margin = horizontal_center + horizontal_margin_to_center
left_margin_node = template_svg.at_css("#left-margin")
left_margin_node["x1"] = adjusted_left_margin.to_s
left_margin_node["x2"] = adjusted_left_margin.to_s
right_margin_node = template_svg.at_css("#right-margin")
right_margin_node["x1"] = adjusted_right_margin.to_s
right_margin_node["x2"] = adjusted_right_margin.to_s

# Make a copy of the modified template.
# In this script we generate only one symbol, but if we end up generating multiple symbols at one it's safer to work on a copy.
symbol_svg = template_svg.dup

default_scale = scale.dup

def replaceNode(xml_id, scale, translation_x, translation_y, symbol_svg, icon_svg)
  # It's finally time to handle that important xml_id node.
  node = symbol_svg.at_css("##{xml_id}")

  # Prepare a transformation matrix from the values calculated above.
  transform_matrix = [
    scale, 0,
    0, scale,
    translation_x, translation_y,
  ].map {|x| "%f" % x } # Convert numbers to strings.
  node["transform"] = "matrix(#{transform_matrix.join(" ")})"

  # Replace the content of the xml_id node with the icon.
  root_dup = icon_svg.root.dup
  node.children = root_dup.children
end

# Move the shape so its center is at the center of the guides.
translation_x = horizontal_center - scaled_width / 2
translation_y = (baseline_y + capline_y) / 2 - scaled_height / 2

space_between_centers = 296.71
font_scales = ["S", "M", "L"]
font_weights = ["Ultralight", "Thin", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black"]
current_symbol_scale = 0.775
symbol_scale_additions = [0.001, 0.002, 0.003, 0.004, 0.04, 0.03, 0.03, 0.06, 0.04]
regular_index = font_weights.find_index("Regular")
medium_index = font_scales.find_index("M")

font_scales.each_with_index { |font_scale, scale_index|
  baseline_y = get_guide_value(template_svg, :y, "Baseline-" + font_scale)
  capline_y = get_guide_value(template_svg, :y, "Capline-" + font_scale)

  font_weights.each_with_index { |font_weight, weight_index|
    current_symbol_scale += symbol_scale_additions[weight_index]
    scale = default_scale * current_symbol_scale
    current_index = weight_index - regular_index
    if (current_index < 0) 
      translation_x = (horizontal_center - (space_between_centers * current_index.abs)) - ((scaled_width * current_symbol_scale) / 2)
    else
      translation_x = (horizontal_center + (space_between_centers * current_index.abs)) - ((scaled_width * current_symbol_scale) / 2)
    end
    translation_y = ((baseline_y + capline_y) / 2) - ((scaled_height * current_symbol_scale) / 2)
    replaceNode(font_weight + "-" + font_scale, scale, translation_x, translation_y, symbol_svg, icon_svg)
  }
}

# Finish by writing the generated symbol to disk.
File.open(DESTINATION_SVG_PATH, "w") do |f|
  symbol_svg.write_to(f)
end
