#!/usr/bin/env ruby

require 'find'
require "fileutils"

class RecursiveDirWalker

   def initialize source_dir
      @source_dirs = [source_dir]
   end

   def walk
      @source_dirs.each do |dir|
         Find.find(dir) do |path|
            if FileTest.directory?(path)
               next
            else
               yield path
            end
         end
      end
   end
end

