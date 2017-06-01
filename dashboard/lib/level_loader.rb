class LevelLoader
  def self.load_custom_levels(level_files = nil)
    level_index = Level.includes(:game).to_a.index_by(&:name)
    if level_files.nil?
      level_files = Dir.glob(Rails.root.join('config/scripts/**/*.level')).sort
    end
    puts "[#{Time.now}] -- Loading levels"
    level_files.map do |path|
      load_custom_level(path, level_index)
    end
    puts "[#{Time.now}] -- Loaded levels"
  end

  def self.levels_used_in_scripts(script_files)
    levels = script_files.map do |script_file|
      script_data, _ = ScriptDSL.parse_file(script_file)
      script_data[:stages].map do |stage|
        stage[:scriptlevels].map do |script_level|
          script_level[:levels].map do |level|
            level_file = Rails.root.join("config/scripts/levels/#{level[:name]}.level")
            if File.file?(level_file)
              level_file
            else
              level_files_for_level_group(level[:name])
            end
          end
        end
      end
    end.flatten.compact
    pp levels
    levels.sort.uniq
  end

  def self.level_files_for_level_group(level_name)
    level_group_file = "config/scripts/#{level_name}.level_group"
    #multi_level_file = "config/scripts/#{level_name}.multi"
    if File.file?(level_group_file)
      puts "Gathering files for level group #{level_name}"
      level_group_data, _ = LevelGroupDSL.parse_file(level_group_file, true)
      [Dir.glob(level_group_file)] + level_group_data[:properties][:pages].map do |page|
        page[:levels].map do |inner_level_name|
          inner_level_file = Rails.root.join("config/scripts/levels/#{inner_level_name}.level")
          if File.file?(inner_level_file)
            Dir.glob(inner_level_file)
          else
            nil
          end
        end
      end
    #elsif File.file(multi_level_file)
    #  puts "Gathering files for multi level #{level_name}"
    #  multi_level_data, _ = MultiDSL.parse_file(multi_level_file, nil, true)
    else
      # It might be a different dsldefined level
      Dir.glob("config/scripts/levels/#{level_name}.*")
    end
  end

  def self.level_file_path(name)
    level_paths = Dir.glob(Rails.root.join("config/scripts/**/#{name}.level"))
    raise("Multiple .level files for '#{name}' found: #{level_paths}") if level_paths.many?
    level_paths.first || Rails.root.join("config/scripts/levels/#{name}.level")
  end

  def self.load_custom_level(level_path, level_index = {})
    name = File.basename(level_path, File.extname(level_path))
    level = (level_index[name] || Level.find_or_create_by(name: name))
    # Only reload level data when file contents change
    level_data = File.read(level_path)
    level.md5 = Digest::MD5.hexdigest(level_data)
    load_custom_level_xml(level_data, level) if level.changed?
    level
  rescue Exception => e
    # print filename for better debugging
    new_e = Exception.new("in level: #{level_path}: #{e.message}")
    new_e.set_backtrace(e.backtrace)
    raise new_e
  end

  def self.load_custom_level_xml(xml, level)
    xml_node = Nokogiri::XML(xml, &:noblanks)
    level = level.with_type(xml_node.root.name)

    # Delete entries for all other attributes that may no longer be specified in the xml.
    # Fixes issue #75863324 (delete removed level properties on import)
    level.send(:write_attribute, 'properties', {})
    level.assign_attributes(level.load_level_xml(xml_node))

    level.save! if level.changed?
    level
  end

  def self.update_unplugged
    # Unplugged level data is specified in 'unplugged.en.yml' file
    unplugged = I18n.t('data.unplugged')
    unplugged_game = Game.find_by(name: 'Unplugged')
    unplugged.map do |name, _|
      Level.where(name: name).first_or_create.update(
        type: 'Unplugged',
        game: unplugged_game
      )
    end
  end
end
