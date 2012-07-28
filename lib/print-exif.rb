#!/usr/bin/env ruby

require 'rubygems'
require 'exifr'

inputDir = ARGV[0]
prefix = ARGV[1].nil? ? "IMG" : ARGV[1]

if (ARGV.length >= 1)
 Dir.glob("#{inputDir}/*.jpg",File::FNM_CASEFOLD).each() {|file|

  timeTaken = EXIFR::JPEG.new(file).date_time

  if (timeTaken.nil? & !EXIFR::JPEG.new(file).exif.nil?)
   timeTaken = EXIFR::JPEG.new(file).exif.date_time_original
  end

  if (timeTaken.nil?)
   #timeTaken = File.mtime(file)
   timeTaken = File.mtime(file)
   puts "Exif data not found for: #{file}"
  else
   puts "Time taken for #{file}: #{timeTaken.strftime('%Y%m%d %H%M%S')}"
  end


 }
else
 puts "JPG_RENAME.rb #IMAGES_FOLDER [FILE_NAME_PREFIX]"
end

