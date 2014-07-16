#!/usr/bin/env ruby

# This script will scan IntelliJ project using IDE's "Inspect Code" feature and abort commit to git repository
# if any error or warning exists.
#
# July 15, 2014
#
# www.gokhanarik.com
#
# Gokhan Arik 

require 'rubygems'
require 'git'
require 'fileutils'
require 'nokogiri'


# Options for log:
#    -v0 Quiet
#    -v1 Noisy
#    -v2 Extra noisy
@options             = "-v0"

@inspection_template = "#{Dir.pwd}/Default.xml"  # Keep your Inspection Template in the same folder with .git 

# Inspection Levels
#
#   Abort Commit if
#       
#       1 Any Error exists.
#       2 Any Warning exists.
#       3 Any Error or Warning exists.
  
@inspection_level = 3 # Level 3 by default

##################
# Helper Methods #
##################

def print_problem ( result )                       
    puts "\n [#{ if result['severity'].casecmp('error') == 0 then result['severity'].upcase.red.bold else result['severity'].upcase.green.bold end}] -> on line #{result['line'].blue.bold} in #{ result['file'].gsub("file://$PROJECT_DIR$", "").magenta }"
    puts "\t Package\t: #{result['package'].green}"
    puts "\t Description\t: #{result['description'].green}"
    puts "\t Type\t\t: #{result['type'].green}"
    puts "\t Problem\t: #{result['fqname'].green}"
end

########################
# Terminal Color Codes #
########################

class String
    def black;          "\033[30m#{self}\033[0m" end
    def red;            "\033[31m#{self}\033[0m" end
    def green;          "\033[32m#{self}\033[0m" end
    def brown;          "\033[33m#{self}\033[0m" end
    def blue;           "\033[34m#{self}\033[0m" end
    def magenta;        "\033[35m#{self}\033[0m" end
    def cyan;           "\033[36m#{self}\033[0m" end
    def gray;           "\033[37m#{self}\033[0m" end
    def bg_black;       "\033[40m#{self}\033[0m" end
    def bg_red;         "\033[41m#{self}\033[0m" end
    def bg_green;       "\033[42m#{self}\033[0m" end
    def bg_brown;       "\033[43m#{self}\033[0m" end
    def bg_blue;        "\033[44m#{self}\033[0m" end
    def bg_magenta;     "\033[45m#{self}\033[0m" end
    def bg_cyan;        "\033[46m#{self}\033[0m" end
    def bg_gray;        "\033[47m#{self}\033[0m" end
    def bold;           "\033[1m#{self}\033[22m" end
    def reverse_color;  "\033[7m#{self}\033[27m" end
end

puts "Running pre-commit script to start code inspection.\n"

##########################
# Find App in Repository #                                                                       
# ######################## 

@git = Git.open(File.expand_path( '#{Dir.pwd}/') ) rescue nil

if @git.nil?
    @git = Git.open(File.expand_path( '#{Dir.pwd}/../') ) rescue nil
    if @git.nil?
        puts "ERROR: Unable to open git repository. Git repository can not be found."
        exit 1 
    else
        @app_path = Dir.glob(File.expand_path( '#{Dir.pwd}/../**/*.iml'))
    end     

else
    @app_path = Dir.glob(File.expand_path( '#{Dir.pwd}/**/*.iml')) rescue nil
end


if @app_path.nil? || @app_path.size == 0 
    puts "There is no .iml file in '#{File.expand_path( '#{Dir.pwd}') }' and its parent directory."
    exit 1
elsif @app_path.size == 1
    # Get the full path for the folder deleting 'filename.iml' part. 
    @app_path = (@app_path[0].split(/(.*)\//) - [""])[0]
else
    exit 1
end

##########################
# Find IntelliJ IDEA Path # 
##########################

if Dir["/Applications/IntelliJ*"] != nil
    @ide_path = Dir["/Applications/IntelliJ*"][0]
    puts "App Path \t: #{@ide_path}"
else
    puts "Intellij IDEA cannot be found in 'Applications' folder."
        exit 1
end

@ide_path = @ide_path.gsub /\s+/, '\ '

###########################################################################
# Create Directory for Inspection Results in Home Folder and Empty Folder #
###########################################################################

@inspection_result_dir = "#{Dir.home}/InspectionResult"

if !File.exists? @inspection_result_dir
    Dir.mkdir @inspection_result_dir
else 
    puts "Emptying folder : #{@inspection_result_dir}"
    FileUtils.rm_rf("#{@inspection_result_dir}/.", secure: true)
end

##################
# Run Inspection #
##################

inspection = "sh #{@ide_path}/bin/inspect.sh #{@app_path} #{@inspection_template} #{@inspection_result_dir} #{@options}"
puts "\nRunning command for inspection... \n"
puts inspection
system inspection

###################
# Analyze Results #
###################

@inspection_stats =  { :error => 0, :warning => 0}
@results = []

Dir.glob( "#{@inspection_result_dir}/*") do |f|
   
    
    file= File.open(f)
    doc = Nokogiri::XML(file)
    
    # Open every XML file in folder and look for Errors and Warnings
    doc.xpath('//problems/problem').each do |i|

        result = Hash.new

        result = {
            'file' => i.xpath('file').text, 
            'severity' => i.xpath('problem_class').attr('severity').text,
            'line' => i.xpath('line').text, 
            'type' => i.xpath('entry_point').attr('TYPE').text,
            'module' => i.xpath('module').text,
            'package' => i.xpath('package').text,
            'fqname' => i.xpath('entry_point').attr('FQNAME').text,
            'description' => i.xpath('description').text,
        }

        @results.push(result)

        if i.xpath('problem_class').attr('severity').text.casecmp("error") == 0
            @inspection_stats[:error] = @inspection_stats[:error] + 1
            print_problem( result )
        elsif i.xpath('problem_class').attr('severity').text.casecmp("warning") == 0
            @inspection_stats[:warning] = @inspection_stats[:warning] + 1
            print_problem( result )
        end

         
    end
    
    file.close

end

###########################
# Final - Commit or Abort #
###########################

puts "Inspection Result"
puts "-----------------"
puts "Error\t:   #{@inspection_stats[:error]}"
puts "Warning\t:    #{@inspection_stats[:warning]}"

case @inspection_level

    when 1

        puts "\nInspection Level 1 - Commit will be aborted if any error exists."
    
        if @inspection_stats[:error] > 0
            puts "\n[Warning] - Please fix these problems before commit. "
            puts "\nAborting commit..."
            exit 1
        else
            exit 0
        end
    when 2

        puts "\nInspection Level 2 - Commit will be aborted if any warning  exists."
        
        if @inspection_stats[:warning] > 0
            puts "\n[Warning] - Please fix these problems before commit. "
            puts "\nAborting commit..."
            exit 1
        else
            exit 0
        end
    when 3
        
        puts "\nInspection Level 3 - Commit will be aborted if any error or warning exists."

        if @inspection_stats[:error] > 0 or @inspection_stats[:warning] > 0
            puts "\n[Warning] - Please fix these problems before commit. "
            puts "\nAborting commit..."
            exit 1
        else
            exit 0
        end
end
