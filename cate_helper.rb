#!/usr/bin/env ruby

require 'open-uri'
require 'mechanize'
require 'nokogiri'
require 'io/console'
require 'zlib'
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# This represents an Imperial College student
#
# :username => IC account username
# :password => IC account password     - needed for downloading files from CATe
# :year     => the year from which you want to retrieve files from    
# :classes  => either Computing or JMC - one of c1, c2, c3, j1, j2, j3 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
Student = Struct.new(:username, :password, :year, :classes)

# Creates a directory in pwd if it doesn't already exist
def createDirectory(directoryName)
  Dir.mkdir(directoryName) unless File.exists?(directoryName)
end

# Downloads file from fileURL into targetDir. 
# Returns false iff file already existed and was not overwritten.
def downloadFileFromURL(targetDir, fileURL, student, override, fileInName)
  # Open file from web URL, using username and password provided
  # credentials = open("http://cate.doc.ic.ac.uk", :http_basic_authentication => [student.username, student.password])
  fileIn = open(fileURL, :http_basic_authentication => [student.username, student.password])
  if(fileInName == "")
    # Extract file name using this snippet found on SO
    begin 
      fileInName = fileIn.meta['content-disposition'].match(/filename=(\"?)(.+)\1/)[2]
    rescue Exception => e
      # puts "Unable to find file name" + e.message
      fileInName = File.basename(URI.parse(fileURL).path)
    end
  end
  # Calculate final path where file will be saved
  fileOutPath = targetDir + '/' + fileInName
  # If file already exists only override if true
  if (!override && File.exists?(fileOutPath)) 
        return false 
  end
  File.open(fileOutPath, 'wb') do |fileOut| 
    fileOut.write fileIn.read 
    return true
  end
end

def download_notes(agent, links, student)
  # exercises = $page.parser.xpath('//b//font//a[contains(text(), "View exercise specification")]').map{|link| link['href']}
  links.each do |link, exercises|
    notes_page = agent.get(link)
    module_name = notes_page.parser.xpath('//center//h3//b')
    module_name = module_name[module_name.size - 1].inner_html
    module_name_split = module_name.split(":")
    module_dir = "[" + module_name_split[0].strip + "] " + module_name_split[1].strip
    working_dir = Dir.pwd 
    resource_dir = "DoC Resources"
    createDirectory(resource_dir)
    Dir.chdir(resource_dir)
    createDirectory(module_dir)
    Dir.chdir(module_dir)
    print_equal
    puts "\nFetching the notes for #{module_dir}..."
    print_equal
    notes_dir = "Notes"
    createDirectory(notes_dir)
    notes = notes_page.parser.xpath('//a[contains(@href, "showfile.cgi?key")]|//a[contains(@title, "doc.ic.ac.uk")]|//a[contains(@title, "resources")]')
    notes.each do |note|
      if(note['href'] == '')
        note_url = open(note['title'], :http_basic_authentication => [student.username, student.password])
        ########################################################################
        ########################################################################
        ##########  If the url points to a pdf => download it ##################
        ##########       Else, redirect & parse for urls      ##################
        ########################################################################
        ########################################################################
        if(note_url.content_type == "application/pdf") 
          puts "Fetching #{note.text()}.pdf..."
          if(downloadFileFromURL(notes_dir, note['title'], student, false, note.text() + ".pdf"))
            print_loading
            puts "\n\t...Success, saved as #{note.text()}.pdf"
          else 
            puts "\t...Skip, #{note.text()}.pdf already exists"
          end
        else
          # check for External Notes
          download_external_notes(notes_dir, note['title'], student, module_dir)
        end
      else # Download local notes
        name = note.text()
        # if(File.extname(note.text()) == "")
        #   name = note.text() + ".pdf" 
        # end
        puts "Fetching #{note.text()}..."
        local_note = agent.page.uri + note['href']
        if(downloadFileFromURL(notes_dir, local_note, student, false, name))
          print_loading
          puts "\n\t...Success, saved as #{name}"
        else 
          puts "\t...Skip, #{name} already exists"
        end
      end
    end
    Dir.chdir(working_dir)
  end
end # End download_notes(links)

def download_external_notes(notes_dir, link, student, module_dir)
  agent = Mechanize.new
  agent.add_auth(link, student.username, student.password)
  external_page = agent.get(link)
  local_notes = external_page.parser.xpath('//a[contains(text(), "Slides")]|//a[@class="resource_title"]|//a[contains(text(), "Handout")]').map{ |link| link['href']  }
  local_notes.each do |local_note| 
    file_name = File.basename(URI.parse(local_note).path)
    puts "Fetching #{file_name}..."
    if(downloadFileFromURL(notes_dir, local_note, student, false, file_name))
      print_loading
      puts "\n\t...Success, saved as #{file_name}.pdf"
    else 
      puts "\t...Skip, #{file_name}.pdf already exists"
    end
  end
  tuts = external_page.parser.xpath('//a[contains(text(), "Question")]')
  sols = external_page.parser.xpath('//a[contains(text(), "Solution")]')
  download_exercises(agent, module_dir, tuts, sols, student)
end

def print_equal
  for i in 1..$cols
    print "="
  end
end # End print_equal

def print_loading
  print "["
  for i in 2..$cols-2
    sleep(1.0/60.0)
    print "#"
  end
  print "]"
end

def download_exercises(agent, module_dir, exercise_row, given_files, student)
  resource_dir = "DoC Resources"
  createDirectory(resource_dir)
  working_dir = Dir.pwd
  Dir.chdir(resource_dir)
  createDirectory(module_dir)
  Dir.chdir(module_dir)
    exercise_row.zip(given_files).each do |exercise, givens| 
      createDirectory(exercise.text())
      exercise_link = agent.page.uri + exercise['href']
      name = exercise.text()
      # if(File.extname(exercise.text()) == "")
      #     name = exercise.text() + ".pdf" 
      # end
      puts "Fetching #{name}..."
      
      if(downloadFileFromURL(exercise.text(), exercise_link, student, false, name))
        print_loading
        puts "\n\t...Success, saved as #{name}"
      else 
        puts "\t...Skip, #{name} already exists"
      end
      
      if(givens != nil)
        page = agent.get(agent.page.uri + givens['href'])  
        models = page.parser.xpath('//a[contains(@href, "MODELS")]')
        models.each do |model| 
          # createDirectory(model.text())
          puts "Fetching #{model.text()}..."
          local_file = "https://cate.doc.ic.ac.uk/" + model['href']
          if(downloadFileFromURL(exercise.text(), local_file, student, false, model.text()))
            print_loading
            puts "\n\t...Success, saved as #{model.text()}"
          else 
            puts "\t...Skip, #{model.text()} already exists"
          end     
        end
        data = page.parser.xpath('//a[contains(@href, "DATA")]')
        data.each do |d| 
          puts "Fetching #{d.text()}..."
          local_file = "https://cate.doc.ic.ac.uk/" + d['href']
          if(downloadFileFromURL(exercise.text(), local_file, student, false, d.text()))
            print_loading
            puts "\n\t...Success, saved as #{d.text()}"
          else 
            puts "\t...Skip, #{d.text()} already exists"
          end     
        end
      end
    end
  Dir.chdir(working_dir)
end # End download_exercises

begin
  if(!ARGV.empty?)
    Dir.chdir(ARGV[0])
    ARGV.pop
  end
################################################################################
#########################          CATe Login        ###########################
################################################################################
  print "IC username: "
  username = gets.chomp
  print "IC password: "
  system "stty -echo"
  password = gets.chomp
  system "stty echo"
  puts ""
  print "Class: " 
  classes = gets.chomp
  print "1 = Autumn\t2 = Christmas\t3 = Spring\t4 = Easter\t5 = Summer\nPeriod: "
  period = gets.chomp
  print "Academic year: "
  year = gets.chomp
  student = Student.new(username, password, year, classes)
  $rows, $cols = IO.console.winsize
  begin
    agent = Mechanize.new
    agent.add_auth('https://cate.doc.ic.ac.uk/' ,student.username, student.password, nil, "https://cate.doc.ic.ac.uk")
    $page = agent.get("https://cate.doc.ic.ac.uk")
    puts "\nLogin Successful, welcome back #{student.username}!\n"

    $page = agent.get("https://cate.doc.ic.ac.uk/timetable.cgi?period=#{period}&class=#{student.classes}&keyt=#{year}%3Anone%3Anone%3A#{student.username}")
    links = $page.parser.xpath('//a[contains(@href, "notes.cgi?key")]').map { |link| link['href'] }.compact.uniq

    ############################################################################
    #######################      Parse the table       #########################
    #######################     one row at a time      #########################
    #######################   get all exercise links   #########################
    #######################  for each row individually #########################
    ############################################################################
    rows = $page.parser.xpath('//tr[./td/a[contains(@title, "View exercise specification")]]')
    module_name = Nokogiri::HTML(rows[0].inner_html).xpath('//b[./font]').text()
    module_name_split = module_name.split("-")
    module_dir = "[" + module_name_split[0] + "] " + module_name_split[1]
    rows.each do |row|
      if(!Nokogiri::HTML(row.inner_html).xpath('//b[./font]').text().nil? && !Nokogiri::HTML(row.inner_html).xpath('//b[./font]').text().empty?)
        module_name = Nokogiri::HTML(row.inner_html).xpath('//b[./font]').text()
        module_name_split = module_name.split("-")        
        module_dir = "[" + module_name_split[0].strip + "] " + module_name_split[1].strip
        print_equal
        puts "\nFetching the exercises for #{module_dir}..."
        print_equal
      end
      exercises1 = Nokogiri::HTML(row.inner_html).xpath('//a[contains(@title, "View exercise specification")]')
      givens = Nokogiri::HTML(row.inner_html).xpath('//a[contains(@href, "given")]')
      # download_exercises(agent, module_dir, exercises1, givens, student)
    end
    download_notes(agent, links, student)
  rescue Exception => e
    puts e.message
  end
  puts "\nAll done! =)"
rescue Exception => e
  puts "> Something went bad :(\n->" + e.message
end
