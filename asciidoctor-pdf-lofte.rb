#  Asciidoctor PDF LoFTE
# Copyright (c) 2024 白一百
# v1.3.0

# This .rb provides AsciiDoctor-PDF with a List of Figures (LoF), a List of Tables (LoT), and a List of Examples (LoE).
# All these lists are styled in a manner matching the built-in Table of Contents (page numbers, dots).
# The caption (title and counter) are inserted at the beginning of the item.
# A header is added at the top of each page.

# This extension works by hooking into AsciiDoctor-PDF's built-in ToC generator.
# Three attributes are in use:
# :lof-title: List of Figures
# :lot-title: List of Tables
# :loe-title: List of Examples
# :lol-title: List of Listings
# To manually disable the inclusion of a list, simply leave the attribute blank or delete it.
# A list will not be printed if the document does not have that type of content (lists, examples, or figures).
# A list will not be printed if it only contains untitled content.
# A list item will not printed if it does not have a title; simply assign a title to the item to make it appear.

# No macroprocessor is available, such as lof::, lot::, or loe::
# Four classes are used, three are for the lists and one for styling the content.
# There is a lot of copy and pasting, but this seems to be necessary
# It is possible to re-order the sections by re-ordering the classes in this .rb file
# It is possible to manually modify the ToC look and feel 


require 'asciidoctor'
require 'asciidoctor/extensions'

## FormatTOC handles the styling/formatting of the lists at the beginning of the book
## The caption (signifier and counter) is inserted on each line, for example "Figure 1."
class FormatTOC < Asciidoctor::Converter.for('pdf')
  register_for 'pdf'

  def ink_toc_level entries, num_levels, dot_leader, num_front_matter_pages
    # NOTE: font options aren't always reliable, so store size separately
    toc_font_info = theme_font :toc do
      { font: font, size: @font_size }
    end
    hanging_indent = @theme.toc_hanging_indent  
    entries.each do |entry|
      next if (num_levels_for_entry = (entry.attr 'toclevels', num_levels).to_i) < (entry_level = entry.level + 1).pred ||
        ((entry.option? 'notitle') && entry == entry.document.last_child && entry.empty?)
      entry_title = entry.context == :section ? entry.numbered_title : (entry.title? ? entry.title : (entry.xreftext 'basic'))
      
      
      ### This space reserved for modifications to ToC/LoF/LoT/LoE style
      if entry.context.to_s == 'section'
        if entry_title == "Table of Contents"
        end
      end
      # entry_title is modified so as not to impact the ToC entries, otherwise it would have "Chapter"
      # Change all images to level 2; otherwise level 1 will be bold
      if entry.context.to_s == 'image' && entry.title != nil
        entry.level = 2
        # entry_title = entry.caption + " " + entry.title
        entry_title = entry.captioned_title
      end
      if entry.context.to_s == 'table' && entry.title != nil
        entry.level = 2
        # entry_title = entry.caption + " " + entry.title
        entry_title = entry.captioned_title

      end
      if entry.context.to_s == 'example' && entry.title != nil
        entry.level = 2
        # entry_title = entry.caption + " " + entry.title
        entry_title = entry.captioned_title
      end
      if entry.context == :listing && entry.title != nil
        entry.level = 2
        # entry_title = entry.caption + " " + entry.title
        entry_title = entry.captioned_title
      end
      
      next if entry_title.nil_or_empty?
      if entry.id == nil
        p "CAUTION: No anchor assigned to `#{entry_title}`. Page number indeterminable. Go assign an anchor [#anchor]. Ignore if intentional."
        next # Skip tables and other items which are intentionally left out of the LoT
      end

      theme_font :toc, level: entry_level do
        entry_title = transform_text entry_title, @text_transform if @text_transform
        pgnum_label_placeholder_width = rendered_width_of_string '0' * @toc_max_pagenum_digits
        # NOTE: only write title (excluding dots and page number) if this is a dry run
        if scratch?
          indent 0, pgnum_label_placeholder_width do
            # NOTE: must wrap title in empty anchor element in case links are styled with different font family / size
            ink_prose entry_title, anchor: true, normalize: false, hanging_indent: hanging_indent, normalize_line_height: true, margin: 0
          end
        else
          entry_anchor = (entry.attr 'pdf-anchor') || entry.id
          if !(physical_pgnum = entry.attr 'pdf-page-start') &&
              (target_page_ref = (get_dest entry_anchor)&.first) &&
              (target_page_idx = state.pages.index {|candidate| candidate.dictionary == target_page_ref })
            physical_pgnum = target_page_idx + 1
          end
          if physical_pgnum
            virtual_pgnum = physical_pgnum - num_front_matter_pages
            pgnum_label = (virtual_pgnum < 1 ? (Asciidoctor::PDF::RomanNumeral.new physical_pgnum, :lower) : virtual_pgnum).to_s
          else
            pgnum_label = '?'
          end
          start_page_number = page_number
          start_cursor = cursor
          start_dots = nil
          entry_title_inherited = (apply_text_decoration ::Set.new, :toc, entry_level).merge anchor: entry_anchor, color: @font_color
          # NOTE: use text formatter to add anchor overlay to avoid using inline format with synthetic anchor tag
          entry_title_fragments = text_formatter.format entry_title, inherited: entry_title_inherited
          line_metrics = calc_line_metrics @base_line_height
          indent 0, pgnum_label_placeholder_width do
            fragment_positions = []
            entry_title_fragments.each do |fragment|
              fragment_positions << (fragment_position = ::Asciidoctor::PDF::FormattedText::FragmentPositionRenderer.new)
              (fragment[:callback] ||= []) << fragment_position
            end
            typeset_formatted_text entry_title_fragments, line_metrics, hanging_indent: hanging_indent, normalize_line_height: true
            break unless (last_fragment_position = fragment_positions.select(&:page_number)[-1])
            start_dots = last_fragment_position.right + hanging_indent
            last_fragment_cursor = last_fragment_position.top + line_metrics.padding_top
            start_cursor = last_fragment_cursor if last_fragment_position.page_number > start_page_number || (start_cursor - last_fragment_cursor) > line_metrics.height
            
          end
          # NOTE: this will leave behind a gap where this entry would have been
          break unless start_dots
          end_cursor = cursor
          move_cursor_to start_cursor
          # NOTE: we're guaranteed to be on the same page as the final line of the entry
          if dot_leader[:width] > 0 #&& (dot_leader[:levels].include? entry_level.pred)
            pgnum_label_width = rendered_width_of_string pgnum_label
            ## To unset the bold font for the page number, uncomment out this line
            # font_styles = Set[]
            pgnum_label_font_settings = { color: @font_color, font: font_family, size: @font_size, styles: font_styles }
            save_font do
              # NOTE: the same font is used for dot leaders throughout toc
              set_font toc_font_info[:font], dot_leader[:font_size]
              font_style dot_leader[:font_style]
              num_dots = [((bounds.width - start_dots - dot_leader[:spacer_width] - pgnum_label_width) / dot_leader[:width]).floor, 0].max
              # FIXME: dots don't line up in columns if width of page numbers differ
              typeset_formatted_text [
                { text: dot_leader[:text] * num_dots, color: dot_leader[:font_color] },
                dot_leader[:spacer],
                ({ text: pgnum_label, anchor: entry_anchor }.merge pgnum_label_font_settings),
              ], line_metrics, align: :right
            end
          else
            typeset_formatted_text [{ text: pgnum_label, color: @font_color, anchor: entry_anchor }], line_metrics, align: :right
          end
          move_cursor_to end_cursor
        end
      end
      indent @theme.toc_indent do
        ink_toc_level (get_entries_for_toc entry), num_levels_for_entry, dot_leader, num_front_matter_pages
      end if num_levels_for_entry >= entry_level
    end
  end

  # This code adds the ToC to the ToC

  def insert_toc_into_toc_section doc, toc_title, toc_page_nums
    if (doc.attr? 'toc-placement', 'macro') && (toc_node = (doc.find_by context: :toc)[0])
      if (parent_section = toc_node.parent).context == :section
        grandparent_section = parent_section.parent
        toc_level = parent_section.level
        insert_idx = (grandparent_section.blocks.index parent_section) + 1
      else
        grandparent_section = doc
        toc_level = doc.sections[0].level
        insert_idx = 0
      end
      toc_dest = toc_node.attr 'pdf-destination'
    else
      grandparent_section = doc
      toc_level = doc.sections[0].level
      insert_idx = 0
      toc_dest = dest_top toc_page_nums.first
    end
    toc_section = Asciidoctor::Section.new grandparent_section, toc_level, false, attributes: { 'pdf-destination' => toc_dest}
    toc_section.title = toc_title
    toc_id = "_toc"
    toc_section.id =  (toc_section.attr 'pdf-anchor') || toc_id
    grandparent_section.blocks.insert insert_idx, toc_section
    toc_section
  end

  def ink_toc(doc, num_levels, toc_page_number, start_cursor, num_front_matter_pages = 0)
    # puts "ink_toc"
    go_to_page toc_page_number unless (page_number == toc_page_number) || scratch?
        start_page_number = page_number
        move_cursor_to start_cursor
        unless (toc_title = doc.attr 'toc-title').nil_or_empty?
          theme_font_cascade [[:heading, level: 2], :toc_title] do
            toc_title_text_align = (@theme.toc_title_text_align || @theme.heading_h2_text_align || @theme.heading_text_align || @base_text_align).to_sym
            ink_general_heading doc, toc_title, align: toc_title_text_align, level: 2, outdent: true, role: :toctitle
            add_dest_for_block doc, id: "_toc", y: (at_page_top? ? page_height : nil)
          end
        end
    unless @toc_extent.nil?
      # puts "Inking LOF"
      # ink_lof(doc, num_levels, @lof_extent.from.page, @lof_extent.from.cursor, num_front_matter_pages)
      toc_title = doc.attr 'toc-title'
      toc_page_nums = @toc_extent&.page_range
      if (doc.attr? 'include-lists-in-toc')
        toc_section = insert_toc_into_toc_section doc, toc_title, toc_page_nums
      end
    end

    super      
  end

  protected

end
    
## List of Figures
class PDFConverterWithLOF < Asciidoctor::Converter.for('pdf')
  register_for 'pdf'

  def allocate_toc(doc, lof_num_levels, toc_start_cursor, break_after_toc)
    # puts "allocate_toc_lof"

    # Don't print the LoF if:
    # 1) There is no content
    # 2) The section was not asked for (no lot-title defined)
    # 3) There are only figures without titles
    
    # Check if there is only content without titles
    blanks = []
    for blank in get_entries_for_lof(doc) do
        if blank.caption != nil
            blanks << blank
        end
    end

    if (doc.attr 'lof-title').nil_or_empty? || get_entries_for_lof(doc).nil_or_empty? || blanks.nil_or_empty?
        result = super
        @loe_extent = nil
        result
    else
        result = super
        @lof_extent = allocate_lof(doc, lof_num_levels, toc_start_cursor, break_after_toc)
        result
    end
  end
    
  def insert_lof_into_toc_section doc, toc_title, toc_page_nums
    if (doc.attr? 'toc-placement', 'macro') && (toc_node = (doc.find_by context: :toc)[0])
      if (parent_section = toc_node.parent).context == :section
        grandparent_section = parent_section.parent
        toc_level = parent_section.level
        insert_idx = (grandparent_section.blocks.index parent_section) + 1
      else
        grandparent_section = doc
        toc_level = doc.sections[0].level
        insert_idx = 0
      end
      toc_dest = toc_node.attr 'pdf-destination'
    else
      grandparent_section = doc
      toc_level = doc.sections[0].level
      insert_idx = 0
      toc_dest = dest_top toc_page_nums.first
    end
    toc_section = Asciidoctor::Section.new grandparent_section, toc_level, false, attributes: { 'pdf-destination' => toc_dest}
    toc_section.title = toc_title
    toc_id = "_lof"
    toc_section.id =  (toc_section.attr 'pdf-anchor') || toc_id
    grandparent_section.blocks.insert insert_idx, toc_section
    toc_section
  end


  def ink_toc(doc, num_levels, toc_page_number, start_cursor, num_front_matter_pages = 0)
    # puts "ink_toc"

    unless @lof_extent.nil?
    #   puts "Inking LOF"
      ink_lof(doc, num_levels, @lof_extent.from.page, @lof_extent.from.cursor, num_front_matter_pages)
      lof_title = doc.attr 'lof-title'
      lof_page_nums = @lof_extent&.page_range
      if (doc.attr? 'include-lists-in-toc')
        lof_section = insert_lof_into_toc_section doc, lof_title, lof_page_nums
      end
    end

    super      
  end

  protected

  def get_entries_for_lof(node)
    # puts "get_entries_for_lof"
    blocks = node.find_by(traverse_documents: true, context: :image) 
    blocks.each { |b| b.title ||= '' }
    blocks
  end

  # This method is a copy of the allocate_toc method, with a brutish find and replace of toc with lof
  def allocate_lof(doc, lof_num_levels, lof_start_cursor, break_after_lof)
    # puts "allocate_lof"
    
    lof_start_page_number = page_number
    to_page = nil
    extent = dry_run onto: self do
      to_page = ink_lof(doc, lof_num_levels, lof_start_page_number, lof_start_cursor).end
      theme_margin :block, :bottom unless break_after_lof
    end
    if to_page > extent.to.page
      extent.to.page = to_page
      extent.to.cursor = bounds.height
    end
    if break_after_lof
      extent.each_page { start_new_page }
    else
      extent.each_page {|first_page| start_new_page unless first_page }
      move_cursor_to extent.to.cursor
    end
    extent
  end

  def ink_lof(doc, num_levels, lof_page_number, start_cursor, num_front_matter_pages = 0)
    # puts "ink_lof"   
    go_to_page lof_page_number unless (page_number == lof_page_number) || scratch?
    start_page_number = page_number
    move_cursor_to start_cursor
    unless (lof_title = doc.attr 'lof-title').nil_or_empty?
      theme_font_cascade [[:heading, level: 2], :lof_title] do
        lof_title_text_align = (@theme.lof_title_text_align || @theme.heading_h2_text_align || @theme.heading_text_align || @base_text_align).to_sym
        ink_general_heading doc, lof_title, align: lof_title_text_align, level: 2, outdent: true, role: :loftitle
        add_dest_for_block doc, id: "_lof", y: (at_page_top? ? page_height : nil)
      end
    end
    unless num_levels < 0
      dot_leader = theme_font :toc do
        if (dot_leader_font_style = @theme.toc_dot_leader_font_style&.to_sym || :normal) != font_style
          font_style dot_leader_font_style
        end
        font_size @theme.toc_dot_leader_font_size
        {
          font_color: @theme.toc_dot_leader_font_color || @font_color,
          font_style: dot_leader_font_style,
          font_size: font_size,
          levels: ((dot_leader_l = @theme.toc_dot_leader_levels) == 'none' ? ::Set.new :
              (dot_leader_l && dot_leader_l != 'all' ? dot_leader_l.to_s.split.map(&:to_i).to_set : (0..num_levels).to_set)),
          text: (dot_leader_text = @theme.toc_dot_leader_content || DotLeaderTextDefault),
          width: dot_leader_text.empty? ? 0 : (rendered_width_of_string dot_leader_text),
          spacer: { text: NoBreakSpace, size: (spacer_font_size = @font_size * 0.25) },
          spacer_width: (rendered_width_of_char NoBreakSpace, size: spacer_font_size),
        }
      end
      theme_margin :toc, :top
      ink_toc_level(get_entries_for_lof(doc), num_levels, dot_leader, num_front_matter_pages)
    end
    lof_page_numbers = (lof_page_number..(lof_page_number + (page_number - start_page_number)))
    go_to_page page_count unless scratch?
    lof_page_numbers
  end
end

# ## List of Tables
# # asciidoctor-pdf extension that attempts to reuse the TOC rendering logic to render the LOT
class PDFConverterWithLOT < Asciidoctor::Converter.for('pdf')
  register_for 'pdf'

  def allocate_toc(doc, lot_num_levels, toc_start_cursor, break_after_toc)
    # puts "allocate_toc_lot"

    # Don't print the LoT if:
    # 1) There is no content
    # 2) The section was not asked for (no lot-title defined)
    # 3) There are only tables without titles
    
    # Check if there is only content without titles
    blanks = []
    for blank in get_entries_for_lot(doc) do
        if blank.caption != nil
            blanks << blank
        end
    end

    if (doc.attr 'lot-title').nil_or_empty? || get_entries_for_lot(doc).nil_or_empty? || blanks.nil_or_empty?
        result = super
        @loe_extent = nil
        result
    else
        result = super
        @lot_extent = allocate_lot(doc, lot_num_levels, toc_start_cursor, break_after_toc)
        result
    end
  end
  
  def ink_toc(doc, num_levels, toc_page_number, start_cursor, num_front_matter_pages = 0)
    # puts "ink_toc"
    unless @lot_extent.nil?
    #   puts "Inking LOT"
      ink_lot(doc, num_levels, @lot_extent.from.page, @lot_extent.from.cursor, num_front_matter_pages)
      lot_title = doc.attr 'lot-title'
      lot_page_nums = @lot_extent&.page_range
      if (doc.attr? 'include-lists-in-toc')
        lot_section = insert_lot_into_toc_section doc, lot_title, lot_page_nums
      end
    end

    super      
  end

  protected

  def get_entries_for_lot(node)
    # puts "get_entries_for_lot"
    blocks = node.find_by(traverse_documents: true, context: :table) # "table" and "example" both work!
    blocks.each { |b| b.title}
    blocks
  end

  # This method is a copy of the allocate_toc method, with a brutish find and replace of toc with lot
  def allocate_lot(doc, lot_num_levels, lot_start_cursor, break_after_lot)
    # puts "allocate_lot"
    
    lot_start_page_number = page_number
    to_page = nil
    extent = dry_run onto: self do
      to_page = ink_lot(doc, lot_num_levels, lot_start_page_number, lot_start_cursor).end      
      theme_margin :block, :bottom unless break_after_lot
    end
    if to_page > extent.to.page
      extent.to.page = to_page
      extent.to.cursor = bounds.height
    end
    if break_after_lot
      extent.each_page { start_new_page }
    else
      extent.each_page {|first_page| start_new_page unless first_page }
      move_cursor_to extent.to.cursor
    end
    extent
  end

  def insert_lot_into_toc_section doc, toc_title, toc_page_nums
    if (doc.attr? 'toc-placement', 'macro') && (toc_node = (doc.find_by context: :toc)[0])
      if (parent_section = toc_node.parent).context == :section
        grandparent_section = parent_section.parent
        toc_level = parent_section.level
        insert_idx = (grandparent_section.blocks.index parent_section) + 1
      else
        grandparent_section = doc
        toc_level = doc.sections[0].level
        insert_idx = 0
      end
      toc_dest = toc_node.attr 'pdf-destination'
    else
      grandparent_section = doc
      toc_level = doc.sections[0].level
      insert_idx = 0
      toc_dest = dest_top toc_page_nums.first
    end
    toc_section = Asciidoctor::Section.new grandparent_section, toc_level, false, attributes: { 'pdf-destination' => toc_dest}
    toc_section.title = toc_title
    toc_id = "_lot"
    toc_section.id =  (toc_section.attr 'pdf-anchor') || toc_id
    grandparent_section.blocks.insert insert_idx, toc_section
    toc_section
  end

  # This method is a copy of the ink_toc method, with a partial find and replace of "toc" with "lot".
  #
  # Much of this logic seems to deal with styling and themes, 
  # and it will be a matter of preference how much should be inherited from the TOC styling.
  def ink_lot(doc, num_levels, lot_page_number, start_cursor, num_front_matter_pages = 0)
    # puts "ink_lot"
    go_to_page lot_page_number unless (page_number == lot_page_number) || scratch?
    start_page_number = page_number
    move_cursor_to start_cursor
    unless (lot_title = doc.attr 'lot-title').nil_or_empty?
      theme_font_cascade [[:heading, level: 2], :lot_title] do
        lot_title_text_align = (@theme.lot_title_text_align || @theme.heading_h2_text_align || @theme.heading_text_align || @base_text_align).to_sym        
        ink_general_heading doc, lot_title, align: lot_title_text_align, level: 2, outdent: true, role: :lottitle
        add_dest_for_block doc, id: "_lot", y: (at_page_top? ? page_height : nil)
      end
    end
    unless num_levels < 0
      dot_leader = theme_font :toc do
        if (dot_leader_font_style = @theme.toc_dot_leader_font_style&.to_sym || :normal) != font_style
          font_style dot_leader_font_style
        end
        font_size @theme.toc_dot_leader_font_size
        {
          font_color: @theme.toc_dot_leader_font_color || @font_color,
          font_style: dot_leader_font_style,
          font_size: font_size,
          levels: ((dot_leader_l = @theme.toc_dot_leader_levels) == 'none' ? ::Set.new :
              (dot_leader_l && dot_leader_l != 'all' ? dot_leader_l.to_s.split.map(&:to_i).to_set : (0..num_levels).to_set)),
          text: (dot_leader_text = @theme.toc_dot_leader_content || DotLeaderTextDefault),
          width: dot_leader_text.empty? ? 0 : (rendered_width_of_string dot_leader_text),
          spacer: { text: NoBreakSpace, size: (spacer_font_size = @font_size * 0.25) },
          spacer_width: (rendered_width_of_char NoBreakSpace, size: spacer_font_size),
        }
      end
      theme_margin :toc, :top
      ink_toc_level(get_entries_for_lot(doc), num_levels, dot_leader, num_front_matter_pages)
    end
    lot_page_numbers = (lot_page_number..(lot_page_number + (page_number - start_page_number)))
    go_to_page page_count unless scratch?
    lot_page_numbers
  end
end

## List of Examples
# asciidoctor-pdf extension that attempts to reuse the TOC rendering logic to render the LOE
class PDFConverterWithLOE < Asciidoctor::Converter.for('pdf')
  register_for 'pdf'

  def allocate_toc(doc, loe_num_levels, toc_start_cursor, break_after_toc)
    # puts "allocate_toc_loe"
    
    # Don't print the LoE if:
    # 1) There is no content
    # 2) The section was not asked for (no lot-title defined)
    # 3) There are only figures without titles
    
    # Check if there is only content without titles
    blanks = []
    for blank in get_entries_for_loe(doc) do
        if blank.caption != nil
            blanks << blank
        end
    end

    if (doc.attr 'loe-title').nil_or_empty? || get_entries_for_loe(doc).nil_or_empty? || blanks.nil_or_empty?
        result = super
        @loe_extent = nil
        result
    else
        result = super
        @loe_extent = allocate_loe(doc, loe_num_levels, toc_start_cursor, break_after_toc)
        result
    end
  end
  

  def ink_toc(doc, num_levels, toc_page_number, start_cursor, num_front_matter_pages = 0)
    # puts "ink_toc"

    unless @loe_extent.nil?
    #   puts "Inking LOE"
      ink_loe(doc, num_levels, @loe_extent.from.page, @loe_extent.from.cursor, num_front_matter_pages)
      loe_title = doc.attr 'loe-title'
      loe_page_nums = @loe_extent&.page_range
      if (doc.attr? 'include-lists-in-toc')
        loe_section = insert_loe_into_toc_section doc, loe_title, loe_page_nums
      end
    end

    super      
  end

  protected

  def get_entries_for_loe(node)
    # puts "get_entries_for_loe"
    blocks = node.find_by(traverse_documents: true, context: :example) # "table" and "example" both work!
    blocks.each { |b| b.title ||= '' }
    blocks
  end

  # This method is a copy of the allocate_toc method, with a brutish find and replace of toc with loe
  def allocate_loe(doc, loe_num_levels, loe_start_cursor, break_after_loe)
    # puts "allocate_loe"
    
    loe_start_page_number = page_number
    to_page = nil
    extent = dry_run onto: self do
      to_page = ink_loe(doc, loe_num_levels, loe_start_page_number, loe_start_cursor).end
      theme_margin :block, :bottom unless break_after_loe
    end
    if to_page > extent.to.page
      extent.to.page = to_page
      extent.to.cursor = bounds.height
    end
    if break_after_loe
      extent.each_page { start_new_page }
    else
      extent.each_page {|first_page| start_new_page unless first_page }
      move_cursor_to extent.to.cursor
    end
    extent
  end


  def ink_loe(doc, num_levels, loe_page_number, start_cursor, num_front_matter_pages = 0)
    # puts "ink_loe"
    
    go_to_page loe_page_number unless (page_number == loe_page_number) || scratch?
    start_page_number = page_number
    move_cursor_to start_cursor
    unless (loe_title = doc.attr 'loe-title').nil_or_empty?
      theme_font_cascade [[:heading, level: 2], :loe_title] do
        loe_title_text_align = (@theme.loe_title_text_align || @theme.heading_h2_text_align || @theme.heading_text_align || @base_text_align).to_sym
        ink_general_heading doc, loe_title, align: loe_title_text_align, level: 2, outdent: true, role: :loetitle
        add_dest_for_block doc, id: "_loe", y: (at_page_top? ? page_height : nil)
      end
    end
    unless num_levels < 0
      dot_leader = theme_font :toc do
        if (dot_leader_font_style = @theme.toc_dot_leader_font_style&.to_sym || :normal) != font_style
          font_style dot_leader_font_style
        end
        font_size @theme.toc_dot_leader_font_size
        {
          font_color: @theme.toc_dot_leader_font_color || @font_color,
          font_style: dot_leader_font_style,
          font_size: font_size,
          levels: ((dot_leader_l = @theme.toc_dot_leader_levels) == 'none' ? ::Set.new :
              (dot_leader_l && dot_leader_l != 'all' ? dot_leader_l.to_s.split.map(&:to_i).to_set : (0..num_levels).to_set)),
          text: (dot_leader_text = @theme.toc_dot_leader_content || DotLeaderTextDefault),
          width: dot_leader_text.empty? ? 0 : (rendered_width_of_string dot_leader_text),
          spacer: { text: NoBreakSpace, size: (spacer_font_size = @font_size * 0.25) },
          spacer_width: (rendered_width_of_char NoBreakSpace, size: spacer_font_size),
        }
      end
      theme_margin :toc, :top
      ink_toc_level(get_entries_for_loe(doc), num_levels, dot_leader, num_front_matter_pages)
    end
    loe_page_numbers = (loe_page_number..(loe_page_number + (page_number - start_page_number)))
    go_to_page page_count unless scratch?
    loe_page_numbers
  end
  def insert_loe_into_toc_section doc, toc_title, toc_page_nums
    if (doc.attr? 'toc-placement', 'macro') && (toc_node = (doc.find_by context: :toc)[0])
      if (parent_section = toc_node.parent).context == :section
        grandparent_section = parent_section.parent
        toc_level = parent_section.level
        insert_idx = (grandparent_section.blocks.index parent_section) + 1
      else
        grandparent_section = doc
        toc_level = doc.sections[0].level
        insert_idx = 0
      end
      toc_dest = toc_node.attr 'pdf-destination'
    else
      grandparent_section = doc
      toc_level = doc.sections[0].level
      insert_idx = 0
      toc_dest = dest_top toc_page_nums.first
    end
    toc_section = Asciidoctor::Section.new grandparent_section, toc_level, false, attributes: { 'pdf-destination' => toc_dest}
    toc_section.title = toc_title
    toc_id = "_loe"
    toc_section.id =  (toc_section.attr 'pdf-anchor') || toc_id
    grandparent_section.blocks.insert insert_idx, toc_section
    toc_section
  end
end


## List of Listings ## Code Snippets
# asciidoctor-pdf extension that attempts to reuse the TOC rendering logic to render the LOE
class PDFConverterWithLOL < Asciidoctor::Converter.for('pdf')
  register_for 'pdf'

  def allocate_toc(doc, lol_num_levels, toc_start_cursor, break_after_toc)
    # puts "allocate_toc_lol"
    
    # Don't print the LoL if:
    # 1) There is no content
    # 2) The section was not asked for (no lot-title defined)
    # 3) There are only figures without titles
    
    # Check if there is only content without titles
    blanks = []
    for blank in get_entries_for_lol(doc) do
        if blank.caption != nil
            blanks << blank
        end
    end

    if (doc.attr 'lol-title').nil_or_empty? || get_entries_for_lol(doc).nil_or_empty? || blanks.nil_or_empty?
        result = super
        @lol_extent = nil
        result
    else
        result = super
        @lol_extent = allocate_lol(doc, lol_num_levels, toc_start_cursor, break_after_toc)
        result
    end
  end
  

  def ink_toc(doc, num_levels, toc_page_number, start_cursor, num_front_matter_pages = 0)
    # puts "ink_toc"

    unless @lol_extent.nil?
    #   puts "Inking LOE"
      ink_lol(doc, num_levels, @lol_extent.from.page, @lol_extent.from.cursor, num_front_matter_pages)
      lol_title = doc.attr 'lol-title'
      lol_page_nums = @lol_extent&.page_range
      if (doc.attr? 'include-lists-in-toc')
        lol_section = insert_lol_into_toc_section doc, lol_title, lol_page_nums
      end
    end

    super      
  end

  protected

  def get_entries_for_lol(node)
    # puts "get_entries_for_lol"
    blocks = node.find_by(traverse_documents: true, context: :listing) # "table" and "example" both work!
    blocks.each { |b| b.title ||= '' }
    blocks
  end

  # This method is a copy of the allocate_toc method, with a brutish find and replace of toc with lol
  def allocate_lol(doc, lol_num_levels, lol_start_cursor, break_after_lol)
    # puts "allocate_lol"
    
    lol_start_page_number = page_number
    to_page = nil
    extent = dry_run onto: self do
      to_page = ink_lol(doc, lol_num_levels, lol_start_page_number, lol_start_cursor).end
      theme_margin :block, :bottom unless break_after_lol
    end
    if to_page > extent.to.page
      extent.to.page = to_page
      extent.to.cursor = bounds.height
    end
    if break_after_lol
      extent.each_page { start_new_page }
    else
      extent.each_page {|first_page| start_new_page unless first_page }
      move_cursor_to extent.to.cursor
    end
    extent
  end


  def ink_lol(doc, num_levels, lol_page_number, start_cursor, num_front_matter_pages = 0)
    # puts "ink_lol"
    
    go_to_page lol_page_number unless (page_number == lol_page_number) || scratch?
    start_page_number = page_number
    move_cursor_to start_cursor
    unless (lol_title = doc.attr 'lol-title').nil_or_empty?
      theme_font_cascade [[:heading, level: 2], :lol_title] do
        lol_title_text_align = (@theme.lol_title_text_align || @theme.heading_h2_text_align || @theme.heading_text_align || @base_text_align).to_sym
        ink_general_heading doc, lol_title, align: lol_title_text_align, level: 2, outdent: true, role: :loltitle
        add_dest_for_block doc, id: "_lol", y: (at_page_top? ? page_height : nil)
      end
    end
    unless num_levels < 0
      dot_leader = theme_font :toc do
        if (dot_leader_font_style = @theme.toc_dot_leader_font_style&.to_sym || :normal) != font_style
          font_style dot_leader_font_style
        end
        font_size @theme.toc_dot_leader_font_size
        {
          font_color: @theme.toc_dot_leader_font_color || @font_color,
          font_style: dot_leader_font_style,
          font_size: font_size,
          levels: ((dot_leader_l = @theme.toc_dot_leader_levels) == 'none' ? ::Set.new :
              (dot_leader_l && dot_leader_l != 'all' ? dot_leader_l.to_s.split.map(&:to_i).to_set : (0..num_levels).to_set)),
          text: (dot_leader_text = @theme.toc_dot_leader_content || DotLeaderTextDefault),
          width: dot_leader_text.empty? ? 0 : (rendered_width_of_string dot_leader_text),
          spacer: { text: NoBreakSpace, size: (spacer_font_size = @font_size * 0.25) },
          spacer_width: (rendered_width_of_char NoBreakSpace, size: spacer_font_size),
        }
      end
      theme_margin :toc, :top
      ink_toc_level(get_entries_for_lol(doc), num_levels, dot_leader, num_front_matter_pages)
    end
    lol_page_numbers = (lol_page_number..(lol_page_number + (page_number - start_page_number)))
    go_to_page page_count unless scratch?
    lol_page_numbers
  end
  def insert_lol_into_toc_section doc, toc_title, toc_page_nums
    if (doc.attr? 'toc-placement', 'macro') && (toc_node = (doc.find_by context: :toc)[0])
      if (parent_section = toc_node.parent).context == :section
        grandparent_section = parent_section.parent
        toc_level = parent_section.level
        insert_idx = (grandparent_section.blocks.index parent_section) + 1
      else
        grandparent_section = doc
        toc_level = doc.sections[0].level
        insert_idx = 0
      end
      toc_dest = toc_node.attr 'pdf-destination'
    else
      grandparent_section = doc
      toc_level = doc.sections[0].level
      insert_idx = 0
      toc_dest = dest_top toc_page_nums.first
    end
    toc_section = Asciidoctor::Section.new grandparent_section, toc_level, false, attributes: { 'pdf-destination' => toc_dest}
    toc_section.title = toc_title
    toc_id = "_lol"
    toc_section.id =  (toc_section.attr 'pdf-anchor') || toc_id
    grandparent_section.blocks.insert insert_idx, toc_section
    toc_section
  end
end
# Asciidoctor PDF LoFTE Modify Running Content
# 2024-01-07 # 白一百
# This converter extension modifies the running content to include the List of Figures, List of Tables, and List of Examples
# This is necessary for the {chapter-title> macro to work correctly


class PDFConverterModifyRunningContent < (Asciidoctor::Converter.for 'pdf')
    register_for 'pdf'
    
    def ink_running_content periphery, doc, skip = [1, 1], body_start_page_number = 1
        skip_pages, skip_pagenums = skip
        # NOTE: find and advance to first non-imported content page to use as model page
        return unless (content_start_page_number = state.pages[skip_pages..-1].index {|it| !it.imported_page? })
        content_start_page_number += (skip_pages + 1)
        num_pages = page_count
        prev_page_number = page_number
        go_to_page content_start_page_number
    
        # FIXME: probably need to treat doctypes differently
        is_book = doc.doctype == 'book'
        header = doc.header? ? doc.header : nil
        sectlevels = (@theme[%(#{periphery}_sectlevels)] || 2).to_i
        sections = doc.find_by(context: :section) {|sect| sect.level <= sectlevels && sect != header }
        toc_title = (doc.attr 'toc-title').to_s if (toc_page_nums = @toc_extent&.page_range) # toc_page_nums is a range
        # 2024-1-07 New Additions
        lof_title = (doc.attr 'lof-title').to_s if (lof_page_nums = @lof_extent&.page_range)
        lot_title = (doc.attr 'lot-title').to_s if (lot_page_nums = @lot_extent&.page_range)
        loe_title = (doc.attr 'loe-title').to_s if (loe_page_nums = @loe_extent&.page_range)
        lol_title = (doc.attr 'lol-title').to_s if (lol_page_nums = @lol_extent&.page_range)
        disable_on_pages = @disable_running_content[periphery]
    
        title_method = TitleStyles[@theme[%(#{periphery}_title_style)]]
        # FIXME: we need a proper model for all this page counting
        # FIXME: we make a big assumption that part & chapter start on new pages
        # index parts, chapters and sections by the physical page number on which they start
        part_start_pages = {}
        chapter_start_pages = {}
        section_start_pages = {}
        trailing_section_start_pages = {}
        sections.each do |sect|
        pgnum = (sect.attr 'pdf-page-start').to_i
        if is_book && ((sect_is_part = sect.sectname == 'part') || sect.level == 1)
            if sect_is_part
            part_start_pages[pgnum] ||= sect
            else
            chapter_start_pages[pgnum] ||= sect
            # FIXME: need a better way to indicate that part has ended
            part_start_pages[pgnum] = '' if sect.sectname == 'appendix' && !part_start_pages.empty?
            end
        else
            trailing_section_start_pages[pgnum] = sect
            section_start_pages[pgnum] ||= sect
        end
        end
    
        # index parts, chapters, and sections by the physical page number on which they appear
        # 2024-01-07 Added "::Asciidoctor::PDF::"
        parts_by_page = ::Asciidoctor::PDF::SectionInfoByPage.new title_method
        chapters_by_page = ::Asciidoctor::PDF::SectionInfoByPage.new title_method
        sections_by_page = ::Asciidoctor::PDF::SectionInfoByPage.new title_method
        # QUESTION: should the default part be the doctitle?
        last_part = nil
        # QUESTION: should we enforce that the preamble is a preface?
        last_chap = is_book ? :pre : nil
        last_sect = nil
        sect_search_threshold = 1
        (1..num_pages).each do |pgnum|
        if (part = part_start_pages[pgnum])
            last_part = part
            last_chap = nil
            last_sect = nil
        end
        if (chap = chapter_start_pages[pgnum])
            last_chap = chap
            last_sect = nil
        end
        if (sect = section_start_pages[pgnum])
            last_sect = sect
        elsif part || chap
            sect_search_threshold = pgnum
        # NOTE: we didn't find a section on this page; look back to find last section started
        elsif last_sect
            (sect_search_threshold..(pgnum - 1)).reverse_each do |prev|
            if (sect = trailing_section_start_pages[prev])
                last_sect = sect
                break
            end
            end
        end
        parts_by_page[pgnum] = last_part
        if toc_page_nums&.cover? pgnum
            if is_book
            chapters_by_page[pgnum] = toc_title
            sections_by_page[pgnum] = nil
            else
            chapters_by_page[pgnum] = nil
            sections_by_page[pgnum] = section_start_pages[pgnum] || toc_title
            end
            toc_page_nums = nil if toc_page_nums.end == pgnum
        # 2024-01-07 New additions
        elsif lof_page_nums&.cover? pgnum
            if is_book
            chapters_by_page[pgnum] = lof_title
            sections_by_page[pgnum] = nil
            else
            chapters_by_page[pgnum] = nil
            sections_by_page[pgnum] = section_start_pages[pgnum] || lof_title
            end
            lof_page_nums = nil if lof_page_nums.end == pgnum
        elsif lot_page_nums&.cover? pgnum
            if is_book
            chapters_by_page[pgnum] = lot_title
            sections_by_page[pgnum] = nil
            else
            chapters_by_page[pgnum] = nil
            sections_by_page[pgnum] = section_start_pages[pgnum] || lot_title
            end
            lot_page_nums = nil if lot_page_nums.end == pgnum
        elsif loe_page_nums&.cover? pgnum
            if is_book
            chapters_by_page[pgnum] = loe_title
            sections_by_page[pgnum] = nil
            else
            chapters_by_page[pgnum] = nil
            sections_by_page[pgnum] = section_start_pages[pgnum] || loe_title
            end
            loe_page_nums = nil if loe_page_nums.end == pgnum
        elsif lol_page_nums&.cover? pgnum
            if is_book
            chapters_by_page[pgnum] = lol_title
            sections_by_page[pgnum] = nil
            else
            chapters_by_page[pgnum] = nil
            sections_by_page[pgnum] = section_start_pages[pgnum] || lol_title
            end
            lol_page_nums = nil if lol_page_nums.end == pgnum
        elsif last_chap == :pre
            chapters_by_page[pgnum] = pgnum < body_start_page_number ? doc.doctitle : (doc.attr 'preface-title', 'Preface')
            sections_by_page[pgnum] = last_sect
        else
            chapters_by_page[pgnum] = last_chap
            sections_by_page[pgnum] = last_sect
        end
        end
    
        doctitle = resolve_doctitle doc, true
        # NOTE: set doctitle again so it's properly escaped
        doc.set_attr 'doctitle', doctitle.combined
        doc.set_attr 'document-title', doctitle.main
        doc.set_attr 'document-subtitle', doctitle.subtitle
        doc.set_attr 'page-count', (num_pages - skip_pagenums)
    
        pagenums_enabled = doc.attr? 'pagenums'
        periphery_layout_cache = {}
        # NOTE: this block is invoked during PDF generation, after #write -> #render_file and thus after #convert_document
        repeat (content_start_page_number..num_pages), dynamic: true do
        pgnum = page_number
        # NOTE: don't write on pages which are imported / inserts (otherwise we can get a corrupt PDF)
        next if page.imported_page? || (disable_on_pages.include? pgnum)
        virtual_pgnum = pgnum - skip_pagenums
        pgnum_label = (virtual_pgnum < 1 ? (Asciidoctor::PDF::RomanNumeral.new pgnum, :lower) : virtual_pgnum).to_s
        side = page_side((@folio_placement[:basis] == :physical ? pgnum : virtual_pgnum), @folio_placement[:inverted])
        doc.set_attr 'page-layout', page.layout.to_s
    
        # NOTE: running content is cached per page layout
        # QUESTION: should allocation be per side?
        trim_styles, colspec_dict, content_dict, stamp_names = allocate_running_content_layout doc, page, periphery, periphery_layout_cache
        # FIXME: we need to have a content setting for chapter pages
        content_by_position, colspec_by_position = content_dict[side], colspec_dict[side]
    
        doc.set_attr 'page-number', pgnum_label if pagenums_enabled
        # QUESTION: should the fallback value be nil instead of empty string? or should we remove attribute if no value?
        doc.set_attr 'part-title', ((part_info = parts_by_page[pgnum])[:title] || '')
        if (part_numeral = part_info[:numeral])
            doc.set_attr 'part-numeral', part_numeral
        else
            doc.remove_attr 'part-numeral'
        end
        doc.set_attr 'chapter-title', ((chap_info = chapters_by_page[pgnum])[:title] || '')
        if (chap_numeral = chap_info[:numeral])
            doc.set_attr 'chapter-numeral', chap_numeral
        else
            doc.remove_attr 'chapter-numeral'
        end
        doc.set_attr 'section-title', ((sect_info = sections_by_page[pgnum])[:title] || '')
        doc.set_attr 'section-or-chapter-title', (sect_info[:title] || chap_info[:title] || '')
    
        stamp stamp_names[side] if stamp_names
    
        canvas do
            bounding_box [trim_styles[:content_left][side], trim_styles[:top][side]], width: trim_styles[:content_width][side], height: trim_styles[:height] do
            theme_font_cascade [periphery, %(#{periphery}_#{side})] do
                if trim_styles[:column_rule_color] && (trim_column_rule_width = trim_styles[:column_rule_width]) > 0
                trim_column_rule_spacing = trim_styles[:column_rule_spacing]
                else
                trim_column_rule_width = nil
                end
                prev_position = nil
                ColumnPositions.each do |position|
                next unless (content = content_by_position[position])
                next unless (colspec = colspec_by_position[position])[:width] > 0
                left, colwidth = colspec[:x], colspec[:width]
                if trim_column_rule_width && colwidth < bounds.width
                    if (trim_column_rule = prev_position)
                    left += (trim_column_rule_spacing * 0.5)
                    colwidth -= trim_column_rule_spacing
                    else
                    colwidth -= (trim_column_rule_spacing * 0.5)
                    end
                end
                # FIXME: we need to have a content setting for chapter pages
                if ::Array === content
                    redo_with_content = nil
                    # NOTE: float ensures cursor position is restored and returns us to current page if we overrun
                    float do
                    # NOTE: bounding_box is redundant if both vertical padding and border width are 0
                    bounding_box [left, bounds.top - trim_styles[:padding][side][0] - trim_styles[:content_offset]], width: colwidth, height: trim_styles[:content_height][side] do
                        # NOTE: image vposition respects padding; use negative image_vertical_align value to revert
                        image_opts = content[1].merge position: colspec[:align], vposition: trim_styles[:img_valign]
                        begin
                        image_info = image content[0], image_opts
                        if (image_link = content[2])
                            image_info = { width: image_info.scaled_width, height: image_info.scaled_height } unless image_opts[:format] == 'svg'
                            add_link_to_image image_link, image_info, image_opts
                        end
                        rescue
                        redo_with_content = image_opts[:alt]
                        log :warn, %(could not embed image in running content: #{content[0]}; #{$!.message})
                        end
                    end
                    end
                    if redo_with_content
                    content_by_position[position] = redo_with_content
                    redo
                    end
                else
                    theme_font %(#{periphery}_#{side}_#{position}) do
                    # NOTE: minor optimization
                    if content == '{page-number}'
                        content = pagenums_enabled ? pgnum_label : nil
                    else
                        content = apply_subs_discretely doc, content, drop_lines_with_unresolved_attributes: true, imagesdir: @themesdir
                        content = transform_text content, @text_transform if @text_transform
                    end
                    formatted_text_box (parse_text content, inline_format: [normalize: true]),
                        at: [left, bounds.top - trim_styles[:padding][side][0] - trim_styles[:content_offset] + ((Array trim_styles[:valign])[0] == :center ? font.descender * 0.5 : 0)],
                        color: @font_color,
                        width: colwidth,
                        height: trim_styles[:prose_content_height][side],
                        align: colspec[:align],
                        valign: trim_styles[:valign],
                        leading: trim_styles[:line_metrics].leading,
                        final_gap: false,
                        overflow: :truncate
                    end
                end
                bounding_box [colspec[:x], bounds.top - trim_styles[:padding][side][0] - trim_styles[:content_offset]], width: colspec[:width], height: trim_styles[:content_height][side] do
                    stroke_vertical_rule trim_styles[:column_rule_color], at: bounds.left, line_style: trim_styles[:column_rule_style], line_width: trim_column_rule_width
                end if trim_column_rule
                prev_position = position
                end
            end
            end
        end
        end
    
        go_to_page prev_page_number
        nil
    end
end

# ModifyOutline
# This converter extension modifies the PDF outline to include the List of Figures, List of Tables, and List of Examples
# 2024-01-09 The 'new way' of adding the ToC, LoF, LoT, and LoE means that these are double-added with the default ModifyOutline
# This modification is necessary to prevent the double-addition
class ModifyOutline < Asciidoctor::Converter.for('pdf')
  register_for 'pdf'
  
  def add_outline doc, num_levels, toc_page_nums, num_front_matter_pages, has_front_cover
    if ::String === num_levels
      if num_levels.include? ':'
        num_levels, expand_levels = num_levels.split ':', 2
        num_levels = num_levels.empty? ? (doc.attr 'toclevels', 2).to_i : num_levels.to_i
        expand_levels = expand_levels.to_i
      else
        num_levels = expand_levels = num_levels.to_i
      end
    else
      expand_levels = num_levels
    end
    # 2024-01-03 Add the Asciidoctor module location
    # front_matter_counter = RomanNumeral.new 0, :lower
    front_matter_counter = ::Asciidoctor::PDF::RomanNumeral.new 0, :lower
    
    pagenum_labels = {}

    num_front_matter_pages.times do |n|
      pagenum_labels[n] = { P: (::PDF::Core::LiteralString.new front_matter_counter.next!.to_s) }
    end

    # add labels for each content page, which is required for reader's page navigator to work correctly
    (num_front_matter_pages..(page_count - 1)).each_with_index do |n, i|
      pagenum_labels[n] = { P: (::PDF::Core::LiteralString.new (i + 1).to_s) }
    end


    if (doc.attr 'include-lists-in-toc').nil?
      unless toc_page_nums.none? || (toc_title = doc.attr 'toc-title').nil_or_empty?
        toc_section = insert_toc_section doc, toc_title, toc_page_nums
      end
      # 2024-01-07 New Additions
      lof_page_nums = @lof_extent&.page_range
      lot_page_nums = @lot_extent&.page_range
      loe_page_nums = @loe_extent&.page_range
      lol_page_nums = @lol_extent&.page_range
      unless lof_page_nums.nil? || (lof_title = doc.attr 'lof-title').nil_or_empty?
        lof_section = insert_lof_section doc, lof_title, lof_page_nums
      end
      unless lot_page_nums.nil? || (lot_title = doc.attr 'lot-title').nil_or_empty?
        lot_section = insert_lot_section doc, lot_title, lot_page_nums
      end
      unless loe_page_nums.nil? || (loe_title = doc.attr 'loe-title').nil_or_empty?
        loe_section = insert_loe_section doc, loe_title, loe_page_nums
      end  
      unless lol_page_nums.nil? || (lol_title = doc.attr 'lol-title').nil_or_empty?
        lol_section = insert_lol_section doc, lol_title, lol_page_nums
      end  
    end
    
    outline.define do
        initial_pagenum = has_front_cover ? 2 : 1
        # FIXME: use sanitize: :plain_text on Document#doctitle once available
        if document.page_count >= initial_pagenum && (outline_title = doc.attr 'outline-title') &&
            (outline_title.empty? ? (outline_title = document.resolve_doctitle doc) : outline_title)
          page title: (document.sanitize outline_title), destination: (document.dest_top initial_pagenum)
        end
        # QUESTION: is there any way to get add_outline_level to invoke in the context of the outline?
        document.add_outline_level self, doc.sections, num_levels, expand_levels
      end if doc.attr? 'outline'

      if !(doc.attr 'include-lists-in-toc').nil_or_empty? # 2024-01-09 added
        toc_section&.remove
        # 2024-01-07 Additions
        lof_section&.remove
        lot_section&.remove
        loe_section&.remove
        lol_section&.remove
      end
      

      catalog.data[:PageLabels] = state.store.ref Nums: pagenum_labels.flatten
      primary_page_mode, secondary_page_mode = PageModes[(doc.attr 'pdf-page-mode') || @theme.page_mode]
      catalog.data[:PageMode] = primary_page_mode
      catalog.data[:NonFullScreenPageMode] = secondary_page_mode if secondary_page_mode
      nil
    end

    def insert_lof_section doc, lof_title, lof_page_nums
      grandparent_section = doc
      lof_level = doc.sections[0].level
      insert_idx = 1
      lof_dest = dest_top lof_page_nums.first
      lof_section = ::Asciidoctor::Section.new grandparent_section, lof_level, false, attributes: { 'pdf-destination' => lof_dest }
      lof_section.title = lof_title
      grandparent_section.blocks.insert insert_idx, lof_section
      lof_section
    end
    def insert_lot_section doc, lot_title, lot_page_nums
      grandparent_section = doc
      lot_level = doc.sections[0].level
      insert_idx = 2
      lot_dest = dest_top lot_page_nums.first
      lot_section = ::Asciidoctor::Section.new grandparent_section, lot_level, false, attributes: { 'pdf-destination' => lot_dest }
      lot_section.title = lot_title
      grandparent_section.blocks.insert insert_idx, lot_section
      lot_section
    end
    def insert_loe_section doc, loe_title, loe_page_nums
      grandparent_section = doc
      loe_level = doc.sections[0].level
      insert_idx = 3
      loe_dest = dest_top loe_page_nums.first
      loe_section = ::Asciidoctor::Section.new grandparent_section, loe_level, false, attributes: { 'pdf-destination' => loe_dest }
      loe_section.title = loe_title
      grandparent_section.blocks.insert insert_idx, loe_section
      loe_section
    end
    def insert_lol_section doc, lol_title, lol_page_nums
      grandparent_section = doc
      lol_level = doc.sections[0].level
      insert_idx = 4
      lol_dest = dest_top lol_page_nums.first
      lol_section = ::Asciidoctor::Section.new grandparent_section, lol_level, false, attributes: { 'pdf-destination' => lol_dest }
      lol_section.title = lol_title
      grandparent_section.blocks.insert insert_idx, lol_section
      lol_section
    end
end