# Module for handling the database connection, fetching Pokémon data, and user authentication for the Pokémon web application.
# It includes methods for retrieving Pokémon information, types, effectiveness, evolutions, and user authentication.

require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'byebug'
require 'json'

enable :sessions

module Model
  # Establishes a connection to the SQLite3 database
  # @return [SQLite3::Database] The database connection object
  def db_connection()
    db = SQLite3::Database.new "db/pokemon.db"
    db.results_as_hash = true
    return db
  end

  # Retrieves a list of all Pokémon in the database along with their types and image URLs
  # @return [Array<Hash>] List of Pokémon with their id, name, type1, type2, and image URL
  def pokedex()
    db = db_connection()
    pokemons = db.execute("SELECT p.id, p.name, t1.name AS type1, t2.name AS type2 FROM Pokemons p LEFT JOIN types t1 ON p.type1 = t1.id LEFT JOIN types t2 ON p.type2 = t2.id")

    pokemons.each do |pokemon|
      pokemon["image_url"] = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/#{pokemon["id"]}.png"
    end

    return pokemons
  end

  # Retrieves the image URL for a specific Pokémon
  # @param name [String] The name of the Pokémon
  # @return [String] The URL for the Pokémon's image
  def pokeimg(name)
    pokemon = pokedata(name)
    pokemon["image_url"] = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/#{pokemon["id"]}.png"
    return pokemon["image_url"]
  end

  # Retrieves detailed data for a specific Pokémon
  # @param name [String] The name of the Pokémon
  # @return [Hash] The Pokémon's data including id, name, types, stats, and abilities
  # @raise [Sinatra::NotFound] If the Pokémon is not found in the database
  def pokedata(name)
    db = db_connection()
    name = params[name].strip.capitalize
    pokemon = db.execute("SELECT p.id, p.name, t1.name AS type1, t2.name AS type2, p.hp, p.attack, p.defense, p.sp_attack, p.sp_defense, p.speed, COALESCE(GROUP_CONCAT(pa.ability_name, ', '), '') AS abilities FROM Pokemons p LEFT JOIN types t1 ON p.type1 = t1.id LEFT JOIN types t2 ON p.type2 = t2.id LEFT JOIN pokemon_abilities pa ON p.id = pa.pokemon_id WHERE LOWER(p.name) = LOWER(?) GROUP BY p.id", [name])

    halt 404, "Pokémon not found" if pokemon.empty?
    pokemon = pokemon.first

    return pokemon
  end

  # Retrieves a list of all Pokémon types in the database
  # @return [Array<String>] A list of type names
  def fetch_type()
    db = db_connection()
    all_types = db.execute("SELECT name FROM types").map { |row| row["name"] }
    return all_types
  end

  # Initializes the effectiveness hash for type effectiveness calculations
  # @param all_types [Array<String>] The list of all Pokémon types
  def initialize_effectiveness(all_types)
    @effectiveness = all_types.to_h { |type| [type, 1.0] }
  end

  # Fetches type effectiveness data for specific Pokémon types
  # @param types [Array<String>] A list of Pokémon types
  def fetch_type_effectiveness(types)
    db = db_connection()
    types.each do |type|
      effectiveness_data = db.execute("SELECT atk.name AS attacking_type, te.effectiveness FROM type_effectiveness te JOIN types atk ON te.attacking_type_id = atk.id JOIN types def ON te.defending_type_id = def.id WHERE def.name = ?", [type])

      effectiveness_data.each do |row|
        attack_type = row["attacking_type"]
        effect = row["effectiveness"]

        # Multiply effectiveness for dual-types
        @effectiveness[attack_type] *= effect

        # Ensure 0× effect always remains 0
        @effectiveness[attack_type] = 0.0 if effect == 0.0
      end
    end
  end

  # Ensures that all types are included in the effectiveness list
  # @param all_types [Array<String>] A list of all Pokémon types
  def ensure_effectiveness_includes_all_types(all_types)
    @effectiveness_list = all_types.map { |type| [type, @effectiveness[type] || 1.0] }
  end

  # Formats the effectiveness list for display
  # Divides the effectiveness list into two halves to display them in a structured grid
  def format_effectiveness_list
    first_half = @effectiveness_list[0...9]
    second_half = @effectiveness_list[9...18]

    first_half += [["", ""]] * (9 - first_half.size) if first_half.size < 9
    second_half += [["", ""]] * (9 - second_half.size) if second_half.size < 9

    @effectiveness_list = [
      first_half,  # Row 1: First 9 Type Names
      first_half.map { |type, value| [type, value] },  # Row 2: Effectiveness Values for First 9 Types
      second_half,  # Row 3: Next 9 Type Names
      second_half.map { |type, value| [type, value] }  # Row 4: Effectiveness Values for Next 9 Types
    ]
  end

  # Fetches the evolution data for a Pokémon, including both pre-evolutions and evolutions.
  # This method relies on the instance variable `@pokemon` which should contain the Pokémon's `id`.
  # The evolution data is retrieved based on the Pokémon's id, and returns both pre-evolutions and evolutions.
  # @return [Array<Hash>] A list of evolution data including Pokémon id, name, and evolution condition
  def fetch_evolution()
    db = db_connection()
    return db.execute("SELECT p.id, p.name, e.evolution_condition FROM evolution_chart e JOIN Pokemons p ON e.pokemon_id = p.id OR e.pre_evolution_id = p.id WHERE (e.pre_evolution_id = ? OR e.pokemon_id = ?) AND p.id != ?", [@pokemon["id"], @pokemon["id"], @pokemon["id"]])
  end


  # Handles the creation of a new user account
  # @param username [String] The chosen username
  # @param password [String] The chosen password
  # @param password_confirm [String] The confirmation of the password
  # @return [String] Redirects to the login page or returns an error message if passwords don't match
  def new_acc_auth(username, password, password_confirm)
    if password == password_confirm
      # Add new user
      password_digest = BCrypt::Password.create(password)
      db = SQLite3::Database.new('db/pokemon.db')
      db.execute("INSERT INTO users (username, pwdigest) VALUES (?, ?)", [username, password_digest])
      redirect('/login')
    else
      "Lösenorden matchade inte"
    end
  end

  # Handles the authentication of the current user during login
  # @param username [String] The username for login
  # @param password [String] The password for login
  # @param session [Hash] The session object used to store login data
  # @return [String] A message indicating success or failure of the login attempt
  def curr_acc_auth(username, password, session)
    db = db_connection()
    result = db.execute("SELECT * FROM users WHERE username = ?", [username]).first

    puts "DB Result: #{result.inspect}" # Debugging
    return "Användaren hittades inte" if result.nil?

    pwdigest = result["pwdigest"]
    id = result["id"]
    role = result["role"]

    if BCrypt::Password.new(pwdigest) == password
      session[:id] = id
      session[:username] = result["username"]
      session[:role] = role

      puts "Session after setting: #{session.inspect}" # Debugging

      return "Inloggning lyckades"
    else
      return "Fel lösenord"
    end
  end
end
