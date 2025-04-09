# Web application built with Sinatra, Slim, SQLite3, and BCrypt for handling Pokémon-related data and user authentication.
# This application allows users to search for Pokémon, view details, register, and login. Admins can edit Pokémon data.

require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require 'json'
require_relative './model.rb'

include Model # Wat dis?

enable :sessions

# Helper method to check if the current user is an admin
before do
  @is_admin = session[:role] == "admin"
end

# Root route that renders the homepage
# @return [String] HTML representation of the homepage
get('/') do
  slim(:index)
end

# Route to display the list of Pokémon
# @return [String] HTML representation of the Pokémon list
get('/index') do
  @pokemons = pokedex()
  slim(:index)
end

# Route to display a specific Pokémon's details
# @param name [String] The name of the Pokémon to fetch data for
# @return [String] HTML representation of the Pokémon's details page
get('/index/:name') do
  puts "Session Role: #{session[:role]}"  # Check if it's correctly set
  @pokemon = pokedata(:name)
  @pokemon["image_url"] = pokeimg(:name)
  all_types = fetch_type()
  initialize_effectiveness(all_types)
  types = [@pokemon["type1"], @pokemon["type2"]].compact
  fetch_type_effectiveness(types)
  ensure_effectiveness_includes_all_types(all_types)
  format_effectiveness_list

  # Fetch evolution chain (previous & next evolutions)
  @evolution_chain = fetch_evolution()
  slim(:pokemon)
end

# Search route for fetching Pokémon data based on user query
# @return [JSON] JSON array of Pokémon matching the search query
get('/search_pokemon') do
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

# Route to render the registration form
# @return [String] HTML representation of the registration page
get('/register') do
  slim(:register)
end

# Route for handling user registration via POST request
# @param username [String] The chosen username
# @param password [String] The chosen password
# @param password_confirm [String] The confirmation of the password
# @return [String] Redirects to the login page or returns error message
post('/users/new') do
  username = params[:username]
  password = params[:password]
  password_confirm = params[:password_confirm]
  new_acc_auth(username, password, password_confirm)
end

# Route to render the login form
# @return [String] HTML representation of the login page
get('/login')  do
  slim(:login)
end

# Route for handling user login via POST request
# @param username [String] The username for login
# @param password [String] The password for login
# @return [String] Redirects to the index page if login is successful or returns error message
post('/users/login') do
  username = params[:username]
  password = params[:password]
  halt 400, "Username or password missing" if username.nil? || password.nil?

  result = curr_acc_auth(username, password, session)
  redirect('/index') if result == "Inloggning lyckades"
  result # Returns error message if login fails
end

# Route for handling Pokémon data update, accessible only by admins
# @param name [String] The name of the Pokémon to update
# @param hp [Integer] The updated HP value
# @param attack [Integer] The updated attack value
# @param defense [Integer] The updated defense value
# @param sp_attack [Integer] The updated special attack value
# @param sp_defense [Integer] The updated special defense value
# @param speed [Integer] The updated speed value
# @return [String] Redirects to the Pokémon's page after updating
post('/update_pokemon/:name') do
  halt 403, "Access Denied" unless @is_admin  

  name = params[:name]
  hp = params[:hp]
  attack = params[:attack]
  defense = params[:defense]
  sp_attack = params[:sp_attack]
  sp_defense = params[:sp_defense]
  speed = params[:speed]

  db = db_connection()
  db.execute("UPDATE Pokemons SET hp = ?, attack = ?, defense = ?, sp_attack = ?, sp_defense = ?, speed = ? WHERE name = ?", [hp, attack, defense, sp_attack, sp_defense, speed, name])

  redirect("/index/#{name}")  # Redirect back to Pokémon page
end

# Route to log out the user by clearing the session
# @return [String] Redirects to the index page after logging out
get('/logout') do
  session.clear
  redirect('/index')
end
