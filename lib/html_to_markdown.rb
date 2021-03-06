require "nokogiri"

class HtmlToMarkdown

  class Block < Struct.new(:name, :head, :body, :opened, :markdown)
    def initialize(name, head="", body="", opened=false, markdown=""); super; end
  end

  def initialize(html, opts={})
    @opts = opts || {}
    @doc = Nokogiri::HTML(html)
    remove_whitespaces!
  end

  def remove_whitespaces!
    @doc.traverse do |node|
      if node.is_a? Nokogiri::XML::Text
        node.content = node.content.lstrip if node.previous_element&.description&.block?
        node.content = node.content.lstrip if node.previous_element.nil? && node.parent.description&.block?
        node.content = node.content.rstrip if node.next_element&.description&.block?
        node.content = node.content.rstrip if node.next_element.nil? && node.parent.description&.block?
        node.remove if node.content.empty?
      end
    end
  end

  def to_markdown
    @stack = [Block.new("root")]
    @markdown = ""
    traverse(@doc)
    @markdown << format_block
    @markdown.gsub(/\n{3,}/, "\n\n").strip
  end

  def traverse(node)
    node.children.each { |node| visit(node) }
  end

  def visit(node)
    if node.description&.block? && node.parent&.description&.block? && @stack[-1].markdown.size > 0
      block = @stack[-1].dup
      @markdown << format_block
      block.markdown = ""
      block.opened = true
      @stack << block
    end

    visitor = "visit_#{node.name}"
    respond_to?(visitor) ? send(visitor, node) : traverse(node)
  end

  BLACKLISTED ||= %w{button datalist fieldset form input label legend meter optgroup option output progress select textarea style script}
  BLACKLISTED.each do |tag|
    class_eval <<-RUBY
      def visit_#{tag}(node)
        ""
      end
    RUBY
  end

  def visit_pre(node)
    code = node.children.find { |c| c.name == "code" }
    code_class = code ? code["class"] : ""
    lang = code_class ? code_class[/lang-(\w+)/, 1] : ""
    @stack << Block.new("pre")
    @markdown << "```#{lang}\n"
    traverse(node)
    @markdown << format_block
    @markdown << "```\n"
  end

  def visit_blockquote(node)
    @stack << Block.new("blockquote", "> ", "> ")
    traverse(node)
    @markdown << format_block
  end

  BLOCK_WITH_NEWLINE ||= %w{div p}
  BLOCK_WITH_NEWLINE.each do |tag|
    class_eval <<-RUBY
      def visit_#{tag}(node)
        @stack << Block.new("#{tag}")
        traverse(node)
        @markdown << format_block
        @markdown << "\n"
      end
    RUBY
  end

  BLOCK_LIST ||= %w{menu ol ul}
  BLOCK_LIST.each do |tag|
    class_eval <<-RUBY
      def visit_#{tag}(node)
        @stack << Block.new("#{tag}")
        traverse(node)
        @markdown << format_block
      end
    RUBY
  end

  def visit_li(node)
    parent = @stack.reverse.find { |n| n.name[/ul|ol|menu/] }
    prefix = parent.name == "ol" ? "1. " : "- "
    @stack << Block.new("li", prefix, "  ")
    traverse(node)
    @markdown << format_block
  end

  (1..6).each do |n|
    class_eval <<-RUBY
      def visit_h#{n}(node)
        @stack << Block.new("h#{n}", "#" * #{n} + " ")
        traverse(node)
        @markdown << format_block
      end
    RUBY
  end

  WHITELISTED ||= %w{del ins kbd s small strike sub sup}
  WHITELISTED.each do |tag|
    class_eval <<-RUBY
      def visit_#{tag}(node)
        @stack[-1].markdown << "<#{tag}>"
        traverse(node)
        @stack[-1].markdown << "</#{tag}>"
      end
    RUBY
  end

  def visit_abbr(node)
    @stack[-1].markdown << (node["title"].present? ? %Q[<abbr title="#{node["title"]}">] : "<abbr>")
    traverse(node)
    @stack[-1].markdown << "</abbr>"
  end

  def visit_img(node)
    if @opts[:keep_img_tags]
      @stack[-1].markdown << node.to_html
    else
      title = node["alt"].presence || node["title"].presence
      @stack[-1].markdown << "![#{title}](#{node["src"]})"
    end
  end

  def visit_a(node)
    @stack[-1].markdown << "["
    traverse(node)
    @stack[-1].markdown << "](#{node["href"]})"
  end

  def visit_tt(node)
    @stack[-1].markdown << "`"
    traverse(node)
    @stack[-1].markdown << "`"
  end

  def visit_code(node)
    @stack.reverse.find { |n| n.name["pre"] } ? traverse(node) : visit_tt(node)
  end

  def visit_br(node)
    @stack[-1].markdown << "\n"
  end

  def visit_hr(node)
    @stack[-1].markdown << "\n\n---\n\n"
  end

  def visit_strong(node)
    delimiter = node.text["*"] ? "__" : "**"
    @stack[-1].markdown << delimiter
    traverse(node)
    @stack[-1].markdown << delimiter
  end

  alias :visit_b :visit_strong

  def visit_em(node)
    delimiter = node.text["*"] ? "_" : "*"
    @stack[-1].markdown << delimiter
    traverse(node)
    @stack[-1].markdown << delimiter
  end

  alias :visit_i :visit_em

  def visit_text(node)
    @stack[-1].markdown << node.text.gsub(/\s{2,}/, " ")
  end

  def format_block
    lines = @stack[-1].markdown.each_line.map do |line|
      prefix = @stack.map { |b| b.opened ? b.body : b.head }.join
      @stack.each { |b| b.opened = true }
      prefix + line.rstrip
    end
    @stack.pop
    (lines + [""]).join("\n")
  end

end
