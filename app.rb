require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require 'json'

# Database connection method
def db_connection
  db = SQLite3::Database.new "db/pokemon.db"
  db.results_as_hash = true
  return db
end

get('/') do
  slim(:index)
end

get('/pokedex') do
  db = db_connection
  @pokemons = db.execute("
    SELECT p.id, p.name, t1.name AS type1, t2.name AS type2 FROM Pokemons p LEFT JOIN types t1 ON p.type1 = t1.id LEFT JOIN types t2 ON p.type2 = t2.id")

  @pokemons.each do |pokemon|
    pokemon["image_url"] = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/#{pokemon["id"]}.png"
  end

  slim(:pokedex)
end

get('/pokedex/:name') do
  db = db_connection
  name = params[:name].strip.capitalize

  # Fetch Pokémon data
  @pokemon = db.execute(" SELECT p.id, p.name, t1.name AS type1, t2.name AS type2, p.hp, p.attack, p.defense, p.sp_attack, p.sp_defense, p.speed, COALESCE(GROUP_CONCAT(pa.ability_name, ', '), '') AS abilities FROM Pokemons p LEFT JOIN types t1 ON p.type1 = t1.id LEFT JOIN types t2 ON p.type2 = t2.id LEFT JOIN pokemon_abilities pa ON p.id = pa.pokemon_id WHERE LOWER(p.name) = LOWER(?) GROUP BY p.id", [name])

  halt 404, "Pokémon not found" if @pokemon.empty?
  @pokemon = @pokemon.first 

  # Set Pokémon image URL
  @pokemon["image_url"] = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/#{@pokemon["id"]}.png"

    # Fetch all Pokémon types dynamically from the database
    all_types = db.execute("SELECT name FROM types").map { |row| row["name"] }

  # Initialize @effectiveness to ensure all types default to 1.0 (neutral)
  @effectiveness = all_types.to_h { |type| [type, 1.0] }

  # Fetch type effectiveness from database
  types = [@pokemon["type1"], @pokemon["type2"]].compact
  types.each do |type|
    effectiveness_data = db.execute("SELECT atk.name AS attacking_type, te.effectiveness FROM type_effectiveness te JOIN types atk ON te.attacking_type_id = atk.id JOIN types def ON te.defending_type_id = def.id WHERE def.name = ?",[type])
  

    effectiveness_data.each do |row|
      attack_type = row["attacking_type"]
      effect = row["effectiveness"]

      # Multiply effectiveness for dual-types
      @effectiveness[attack_type] *= effect

      # Ensure 0× effect always remains 0
      @effectiveness[attack_type] = 0.0 if effect == 0.0
    end
  end


  @effectiveness ||= {}  # Prevents nil errors

  # Fetch all Pokémon types dynamically from the database and extract only the names
  all_types = db.execute("SELECT name FROM types").map { |row| row["name"] }

  # Ensure @effectiveness includes all types (default to 1.0 if missing)
  @effectiveness_list = all_types.map { |type| [type, @effectiveness[type] || 1.0] }

  # Reformat into a structured 4x9 grid
  first_half = @effectiveness_list[0...9]
  second_half = @effectiveness_list[9...18]

  # Ensure exactly 9 elements per row by padding with empty slots
  first_half += [["", ""]] * (9 - first_half.size) if first_half.size < 9
  second_half += [["", ""]] * (9 - second_half.size) if second_half.size < 9

  # Structure the data for a 4-row layout
  @effectiveness_list = [
    first_half,  # Row 1: First 9 Type Names
    first_half.map { |type, value| [type, value] },  # Row 2: Effectiveness Values for First 9 Types
    second_half,  # Row 3: Next 9 Type Names
    second_half.map { |type, value| [type, value] }  # Row 4: Effectiveness Values for Next 9 Types
  ]


  # Fetch evolution chain (previous & next evolutions)
  @evolution_chain = db.execute(" SELECT p.id, p.name, e.evolution_condition FROM evolution_chart e JOIN Pokemons p ON e.pokemon_id = p.id OR e.pre_evolution_id = p.id WHERE (e.pre_evolution_id = ? OR e.pokemon_id = ?) AND p.id != ?",[@pokemon["id"], @pokemon["id"], @pokemon["id"]]) 

  slim(:pokemon)
end

get '/search' do
  slim(:search)
end

# Route to return filtered Pokémon in JSON format
get '/search_pokemon' do
  db = db_connection
  query = params[:q].to_s.downcase.strip

  pokemons = db.execute <<-SQL, ["%#{query}%"]
    SELECT Pokemons.id, Pokemons.name, 
           COALESCE(t1.name, 'Unknown') AS type1, 
           COALESCE(t2.name, '') AS type2
    FROM Pokemons
    LEFT JOIN types t1 ON Pokemons.type1 = t1.id
    LEFT JOIN types t2 ON Pokemons.type2 = t2.id
    WHERE LOWER(Pokemons.name) LIKE ?
  SQL

  pokemons.each do |pokemon|
    pokemon["image_url"] = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/#{pokemon['id']}.png"
    pokemon["types"] = pokemon["type2"].empty? ? pokemon["type1"] : "#{pokemon['type1']} / #{pokemon['type2']}"
  end

  content_type :json
  pokemons.to_json
end

