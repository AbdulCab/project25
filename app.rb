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
  protected_routes_user = ['/team_builder', '/update_team']
  # Check if the user is logged in for protected routes
  if protected_routes_user.include?(request.path_info) && session[:user_id].nil?
    session[:error] = "Du måste vara inloggad för att komma åt denna sida."
    redirect '/login'
  end
  # Check if the user is an admin for admin routes
  protected_routes_admin = ['/update_pokemon/:name', '/administration']
  if protected_routes_admin.include?(request.path_info) && !@is_admin
    session[:error] = "Endast administratörer har åtkomst till denna sida."
    redirect '/index'
  end
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

  result = new_acc_auth(username, password, password_confirm)
  if result == "Registrering lyckades"
    redirect('/login')  # Redirect to login page if registration is successful
  else
    @error = result  # Pass the error message to the view
    slim(:register)  # Render the registration page with the error
  end
end


# Route for handling user login via POST request
# @param username [String] The username for login
# @param password [String] The password for login
# @return [String] Redirects to the index page if login is successful or returns error message
post('/users/login') do
  username = params[:username]
  password = params[:password]

  # Initiera sessionsvariabler för att spåra försök
  session[:login_attempts] ||= 0
  session[:first_attempt_time] ||= Time.now

  # Kontrollera om användaren har gjort fler än 5 försök inom 30 sekunder
  if session[:login_attempts] >= 5 && Time.now - session[:first_attempt_time] < 30
    session[:last_login_attempt] = Time.now unless session[:last_login_attempt]
    redirect '/login'
  end

  # Återställ räknaren om 30 sekunder har passerat sedan första försöket
  if Time.now - session[:first_attempt_time] >= 30
    session[:login_attempts] = 0
    session[:first_attempt_time] = Time.now
  end

  # Kontrollera om användarnamn och lösenord är tomma
  if username.nil? || username.empty? || password.nil? || password.empty?
    session[:error] = "Användarnamn och lösenord får inte vara tomma."
    session[:login_attempts] += 1
    redirect '/login'
  end

  # Försök att autentisera användaren
  result = curr_acc_auth(username, password, session)
  if result == "Inloggning lyckades"
    session.delete(:login_attempts) # Rensa försök vid lyckad inloggning
    session.delete(:first_attempt_time)
    session.delete(:last_login_attempt)
    redirect('/index')
  else
    session[:error] = result # Spara felmeddelandet i sessionen
    session[:login_attempts] += 1
    redirect '/login'
  end
end

# Route to render the login form
# @return [String] HTML representation of the login page
get('/login') do
  @error = session.delete(:error)  # Hämta och ta bort felmeddelandet från sessionen
  if session[:last_login_attempt]
    elapsed_time = Time.now - session[:last_login_attempt]
    @cooldown_time = [30 - elapsed_time.to_i, 0].max # Beräkna återstående tid
  else
    @cooldown_time = 0
  end
  slim(:login)
end

get('/administration') do
  halt 403, "Access Denied" unless @is_admin

  @users = fetch_all_users # Hämta alla användare från databasen
  slim(:administration)
end

post('/users/delete') do
  halt 403, "Access Denied" unless @is_admin

  username = params[:username]
  user = fetch_user_by_username(username) # Hämta användaren från databasen

  if user
    user_id = user["id"] # Hämta användarens ID
    team_delete(user_id) # Ta bort användarens team
    delete_user_by_username(username) # Ta bort användaren från databasen
  end

  redirect '/administration'
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

get('/team_builder') do
  user_id = session[:user_id]
  halt 403, "Du måste vara inloggad för att komma åt denna sida." unless user_id

  team = fetch_team(user_id)
  @pokemons = team ? fetch_team_pokemon_data(team) : []

  slim(:team_builder)
end

get('/update_team') do
  user_id = session[:user_id]
  halt 403, "Du måste vara inloggad för att komma åt denna sida." unless user_id

  team_create(user_id) # Skapa ett team om det inte redan finns
  @team = fetch_team(user_id)
  @pokemons = pokedex() # Hämta alla Pokémon för dropdown-menyer

  slim(:update_team)
end


# Route for handling team builder updates
# @param pokemon1 [String] The name of the first Pokémon
# @param pokemon2 [String] The name of the second Pokémon
# @param pokemon3 [String] The name of the third Pokémon
# @param pokemon4 [String] The name of the fourth Pokémon
# @param pokemon5 [String] The name of the fifth Pokémon
# @param pokemon6 [String] The name of the sixth Pokémon
# @return [String] Redirects to the team builder page after updating
post('/team_updater') do
  user_id = session[:user_id]
  halt 403, "Du måste vara inloggad för att uppdatera ditt team." unless user_id  # Kontrollera om användaren är inloggad


  pokemon1 = params[:pokemon1]
  pokemon2 = params[:pokemon2]
  pokemon3 = params[:pokemon3]
  pokemon4 = params[:pokemon4]
  pokemon5 = params[:pokemon5]
  pokemon6 = params[:pokemon6]

  fetch_team_data(pokemon1, pokemon2, pokemon3, pokemon4, pokemon5, pokemon6) # Hämta teamdata från formuläret
  redirect('/team_builder')
end

# Route to log out the user by clearing the session
# @return [String] Redirects to the index page after logging out
get('/logout') do
  session.clear
  session[:error] = "Du har loggats ut."
  redirect('/login')
end
