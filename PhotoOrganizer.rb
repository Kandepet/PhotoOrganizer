#!/usr/bin/env ruby

require 'find'
require 'exifr'
require "fileutils"
require 'optparse'
require 'pp'
require './lib/PHash'
require './lib/BKTree'
require './lib/DirWalker'

IMAGE_TYPES = [".jpg", ".jpeg"]

class FileOrganizer
   OTHER_DIR = "Other"

   # dup modes
   IGNORE_DUPS = 0
   SKIP_DUPS   = 1
   MARK_DUPS   = 2
   NOT_A_DUP   = -1

   def initialize source_path, dest_dir, threshold
      @source_path = source_path
      @dest_dir = dest_dir
      @threshold = threshold

      verbose "Threshold: #{@threshold}"
      #verbose "Processing:  #{@source_path}"
   end

   def ext
      File.extname(@source_path.downcase)
   end

   def is_image?
      #[".jpg", ".jpeg"].include? ext
      IMAGE_TYPES.include? ext
   end

   def timestamp(file = nil)
      file = @source_path if file == nil
      #exif_file = EXIFR::JPEG.new @source_path
      exif_file = EXIFR::JPEG.new file
      if exif_file.exif? && exif_file.date_time
         return exif_file.date_time
      else
         #return File.new(@source_path).ctime
         return File.new(file).ctime
      end
   end

   def original_name
      File.basename @source_path
   end

   def original_name_without_ext
      original_name.chomp(File.extname(original_name) )
   end

   def path_with_timestamp_without_ext
      file_timestamp = timestamp
      if is_image?
         #return "#{@dest_dir}#{File::SEPARATOR}#{file_timestamp.year}#{File::SEPARATOR}#{file_timestamp.strftime("%b")}#{File::SEPARATOR}#{file_timestamp.strftime("%d - %a")}#{File::SEPARATOR}#{file_timestamp.strftime("%I:%M:%S %p")} - #{original_name_without_ext}"
         return "#{@dest_dir}#{File::SEPARATOR}#{file_timestamp.year}#{File::SEPARATOR}#{file_timestamp.strftime("%b")}#{File::SEPARATOR}#{file_timestamp.strftime("%d-%a")}#{File::SEPARATOR}#{file_timestamp.strftime("%I-%M-%S-%p")}"
      else
         return "#{@dest_dir}#{File::SEPARATOR}#{OTHER_DIR}#{File::SEPARATOR}#{original_name_without_ext}"
      end
   end

   def path_with_timestamp(append = "")
      return "#{path_with_timestamp_without_ext}#{append}#{ext}"
   end

   def file_with_same_name_exists?(path)
      exists = File.exists? path
      #verbose "File #{path} exists = #{exists}"
      return exists
   end

   def dest_path(mode, append = "")

      path = path_with_timestamp(append)
      count = 1
      while(file_with_same_name_exists?(path))
         #verbose "File #{path} exists, incrementing"
         path = path_with_timestamp("#{append}-COPY_#{count}")
         count += 1
      end

      return path
   end

   def is_duplicate?(fingerprints, hash)
      return fingerprints.get_matches?(hash, @threshold)
   end

   def copy(fingerprints, mode)

      # Figure out the path to copy to.
      #verbose "MODE: #{mode}"
      if mode == IGNORE_DUPS
         #verbose "copy: Ignoring dups"
         # Don't care about dups, copy the file.
         dest_path_v = dest_path(IGNORE_DUPS)
      else
         # Need to check for duplicates

         image_hash = PHash::image_hash(@source_path)
         #verbose "DUP DETECTION for: #{image_hash}"
         dup_hash = is_duplicate?(fingerprints, image_hash) #dup_hash is either the hash of a duplicate image or false
         if dup_hash != false
            # Found a duplicate image.
            verbose "FOUND A DUP"
            if mode == SKIP_DUPS
               # Skipping it
               verbose "SKIPPING: #{image_hash} is a dup"
               return
            elsif mode == MARK_DUPS
               distance = dup_hash.distance(image_hash)
               verbose "FOUND DISTANCE: #{distance}"
               if distance == 0
                  verbose "SKIPPING EXACT MATCH"
                  return
               end

               verbose "WILL MARK AS DUP"
               # Need to find a suitable name for the dup
               dup_timestamp = timestamp(dup_hash.path)
               append = "-DUPLICATE_OF-#{dup_timestamp.year}-#{dup_timestamp.strftime("%b")}-#{dup_timestamp.strftime("%d")}-#{dup_timestamp.strftime("%I-%M-%S-%p")}"
               verbose "Appending: #{append}"
               dest_path_v = dest_path(MARK_DUPS, append)
               verbose "Destination path: #{dest_path_v}"
            end
         else
            verbose "NOT A DUPE"
            dest_path_v = dest_path(NOT_A_DUP) #-1 to skip the duplicate
         end
      end

      #irrespective of if it is a dup or not, save the fingerprint.
      # change the path in the hash to the file's new path
      image_hash.path = dest_path_v
      fingerprints.add image_hash

      verbose "COPYING: #{@source_path} to #{dest_path_v}"
      puts " "
      FileUtils.mkdir_p File.dirname dest_path_v
      FileUtils.cp  @source_path, dest_path_v
   end
end

class FingerPrints

   def initialize
      @bktree = BK::Tree.new
   end

   def is_image?(file)
      [".jpg", ".jpeg"].include? File.extname(file.downcase)
   end

   def scan(path)
      if is_image?(path)
         verbose "FINGERPRINTING: #{path}"
         image_hash = PHash::image_hash(path)
         @bktree.add image_hash
      else
         verbose "FINGERPRINTING: SKIPPING #{path}"
      end
   end

   def get_matches?(hash, threshold)
      verbose "Threshold: #{threshold}"
      #Convert threshold to a distance.
      distance = (1 - threshold) * 64
      #distance = (@threshold) * 64

      matched_prints = @bktree.query(hash, distance.ceil)

      verbose "FingerPrints: distance: #{distance.ceil} : #{matched_prints}"

      if matched_prints.size > 0
         min_distance = 100 #max distance is 64, so setting to 100 guarantees that we find the best match.
         best_match = nil
         matched_prints.each { |seen, distance|
            verbose "MATCHED: #{seen} distance: #{distance}"

            return seen if distance == 0 # Can't do better than an exact match.

            if (distance < min_distance)
               min_distance = distance
               best_match = seen
            end
         }

         verbose "BEST MATCHED: #{best_match} distance: #{min_distance}"
         return best_match
      end
      return false
   end

   def add(hash)
      verbose "Fingerprint:add -> #{hash}"
      @bktree.add hash
   end

   def dump
      pp @bktree.dump
   end

   def load(path)
      fingerprints_file = "#{path}#{File::SEPARATOR}fingerprints.data"
      if File.exists? fingerprints_file
         #@fingerprints.import(fingerprints_file)
         file = File.open(fingerprints_file, 'r')
         @bktree = Marshal.load file.read
         file.close

         return true
      else
         return false
      end

   end

   def store(path)
      fingerprints_file = "#{path}#{File::SEPARATOR}fingerprints.data"

      marshal_dump = Marshal.dump(@bktree)
      file = File.new(fingerprints_file,'w')
      #file = Zlib::GzipWriter.new(file) unless options[:gzip] == false
      file.write marshal_dump
      file.close
   end

end


class PhotoOrganizer

   def initialize
      @fingerprints = FingerPrints.new
   end

   def organize options

      # If the output directory contains a fingerprints.data file, load it and skip scanning
      # else scan and load the fingerprints of all files in the output directory
      if !@fingerprints.load(options[:output_dir])
         verbose "No fingerprints.data file found. Scanning images in #{options[:output_dir]}"

         RecursiveDirWalker.new(options[:output_dir]).walk do |file|
            @fingerprints.scan(file)
         end

         # Save the scanned files so we can skip this next time.
         @fingerprints.store(options[:output_dir])
      end
      @fingerprints.dump

      #process the new files
      RecursiveDirWalker.new(options[:input_dir]).walk do |file|
         FileOrganizer.new(file, options[:output_dir], options[:threshold]).copy(@fingerprints, options[:mode])
      end

      #save the latest fingerprints so we can skip this next time.
      @fingerprints.store(options[:output_dir])
   end

end

$options = {}
option_parser = OptionParser.new do |o|
   o.on('-d [0/1/2]', "Enable duplicate detection. The mode signifies the action to take",
        "0 = No duplicate detection. Copy all files",
        "1 = Detect and skip all duplicates (use -t to set duplicate detection threshold)",
        "2 = Detect and skip exact copies, but mark other duplicates (use -t to set duplicate detection threshold)",
        "You could use mode 2 for keeping bracketed images", " ") { |b|
           if b == nil
              b = 0
           end

           b = b.to_i

           if ((b < 0) || (b > 2))
              puts "ERROR: unknown duplicate detection mode: #{b}"
              puts option_parser
              exit
           end

           $options[:mode] = b
        }
   o.on('-i INPUT_DIR') { |path| $options[:input_dir] = path }
   o.on('-o OUTPUT_DIR') { |path| $options[:output_dir] = path }
   o.on('-t THRESHOLD', "Control the duplicate detection threshold",
        "default = 0.9",
        "threshold = 0.8 preserves bracketed images (exposure/flash compensated)",
        "threshold = 0.6 keeps images resized, cropped, etc", " ") { |t| $options[:threshold] = t.to_f }
   o.on('-h', "Help") { puts o; exit }
   o.on('-v', "Verbose") { |b| $options[:verbose] = b }
end

begin
   option_parser.parse!
rescue OptionParser::ParseError
   puts option_parser
   exit
end

unless $options[:input_dir] && $options[:output_dir]
   puts "ERROR: Both INPUT & OUTPUT directory is needed"
   puts option_parser
   exit;
end

def verbose(str)
   if $options[:verbose]
      puts str
   end
end


$options[:verbose] = true
#remove any trailing /
$options[:input_dir] = $options[:input_dir].sub(/(#{File::SEPARATOR})+$/,'')
$options[:output_dir] = $options[:output_dir].sub(/(#{File::SEPARATOR})+$/,'')

puts "Starting Duplicate Detection"
#PhotoOrganizer.new.organize $options
organizer = PhotoOrganizer.new
organizer.organize $options

