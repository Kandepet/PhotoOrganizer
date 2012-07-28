#!/usr/bin/env ruby

require 'rubygems'
require 'RMagick'


image_file = ARGV[0]

p "Resizing #{image_file}"

img = Magick::Image.read(image_file).first
target = Magick::Image.new(100, 100) do
  self.background_color = 'white'
end
img.resize_to_fit!(500, 500)
target.composite(img, Magick::CenterGravity, Magick::CopyCompositeOp).write("small.jpg")
