# Author:
# ======
# LA Rafael
# larafael@mailchuck.com

module Jekyll
  require 'microformats2'

  class JSONGenerator < Generator
    safe true
    priority :low

    def generate(site)
      # Converter for .md > .html
      converter = site.getConverterImpl(Jekyll::Converters::Markdown)

      # Iterate over all posts
      site.posts.each do |post|

        # Encode the HTML to JSON
        #hash = { "content" => converter.convert(post.content)}      
        title = post.title.downcase.tr(' ', '-').delete("'!")
        # Start building the path
        path = "json/"

        # Add categories to path if they exist
   #     if (post.data['categories'].class == String)
    #      path << post.data['categories'].tr(' ', '/')
    #    elsif (post.data['categories'].class == Array)
    #      path <<  post.data['categories'].join('/')
    #    end
    # Add the sanitized post title to complete the path
         path << "/#{title}"

        # Create the directories from the path
        FileUtils.mkpath(path) unless File.exists?(path)

        content="<div class='h-entry'>#{converter.convert(post.content)}</div>"
        # Create the JSON file and inject the data
        collection = Microformats2.parse(content)
        f = File.new("#{path}/#{title}.json", "w+")
        f.puts  collection.to_json
      end

    end

  end

end
