require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require 'json'
require_relative './model.rb'

include Model
enable :sessions

# ---------------------------------------
# BEFORE FILTERS
# ---------------------------------------

# Checks user authentication and authorization before processing requests
#
before do
  @is_admin = session[:role] == "admin"
  
  protected_routes_user = ['/teams', '/teams/edit']
  protected_routes_admin = ['/admin']

  if protected_routes_user.include?(request.path_info) && session[:user_id].nil?
    session[:error] = "Du måste vara inloggad för att komma åt denna sida."
    redirect '/login'
  end

  if protected_routes_admin.include?(request.path_info) && !@is_admin
    session[:error] = "Endast administratörer har åtkomst till denna sida."
    redirect '/pokemons'
  end
  if request.path_info == '/teams' && request.put?
    team = fetch_team(session[:user_id])
    unless team && team["user_id"] == session[:user_id]
      session[:error] = "Du kan bara ändra ditt eget lag."
      redirect '/pokemons'
    end
  end
end



# ---------------------------------------
# PUBLIC ROUTES
# ---------------------------------------

# Displays the landing page
#
get('/') do
  slim(:index)
end

# Displays all Pokémon
#
# @see Model#pokedex
get('/pokemons') do
  @pokemons = pokedex()
  slim(:index)
end

# Displays details for a specific Pokémon
#
# @param [String] name Pokémon name
# @see Model#pokedata
# @see Model#pokeimg
# @see Model#fetch_type
# @see Model#fetch_evolution
get('/pokemons/:name') do
  @pokemon = pokedata(params[:name])
  @pokemon["image_url"] = pokeimg(params[:name])

  all_types = fetch_type()
  initialize_effectiveness(all_types)
  types = [@pokemon["type1"], @pokemon["type2"]].compact

  fetch_type_effectiveness(types)
  ensure_effectiveness_includes_all_types(all_types)
  format_effectiveness_list

  @evolution_chain = fetch_evolution()
  slim(:pokemon)
end

# Searches for Pokémon matching the query
#
# @param [String] q search query
# @return [JSON] Array of Pokémon matching the search
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

# ---------------------------------------
# USER REGISTRATION AND LOGIN
# ---------------------------------------

# Displays the user registration form
#
get('/users/register') do
  slim(:register)
end

# Creates a new user account
#
# @param [String] username
# @param [String] password
# @param [String] password_confirm
# @see Model#new_acc_auth
post('/users') do
  result = new_acc_auth(params[:username], params[:password], params[:password_confirm])
  if result.nil?
    redirect('/login')
  else
    @error = result
    slim(:register)
  end
end

# Displays the login form
#
get('/login') do
  @error = session.delete(:error)
  if session[:last_login_attempt]
    elapsed_time = Time.now - session[:last_login_attempt]
    @cooldown_time = [30 - elapsed_time.to_i, 0].max
  else
    @cooldown_time = 0
  end
  slim(:login)
end

# Authenticates user and creates session
#
# @param [String] username
# @param [String] password
# @see Model#curr_acc_auth
post('/login') do
  username = params[:username]
  password = params[:password]

  session[:login_attempts] ||= 0
  session[:first_attempt_time] ||= Time.now

  if session[:login_attempts] >= 5 && Time.now - session[:first_attempt_time] < 30
    session[:last_login_attempt] ||= Time.now
    redirect '/login'
  end

  if Time.now - session[:first_attempt_time] >= 30
    session[:login_attempts] = 0
    session[:first_attempt_time] = Time.now
  end

  if username.empty? || password.empty?
    session[:error] = "Användarnamn och lösenord får inte vara tomma."
    session[:login_attempts] += 1
    redirect '/login'
  end

  result = curr_acc_auth(username, password, session)
  if result == "Inloggning lyckades"
    session.delete(:login_attempts)
    session.delete(:first_attempt_time)
    session.delete(:last_login_attempt)
    redirect('/pokemons')
  else
    session[:error] = result
    session[:login_attempts] += 1
    redirect '/login'
  end
end

# Ends user session and redirects to pokemons page
#
get('/logout') do
  session.clear
  session[:error] = "Du har loggats ut."
  redirect('/pokemons')
end

# ---------------------------------------
# TEAM BUILDER
# ---------------------------------------

# Displays the user's Pokémon team
#
# @see Model#fetch_team
get('/teams') do
  user_id = session[:user_id]
  team = fetch_team(user_id)
  @pokemons = team ? fetch_team_pokemon_data(team) : []
  slim(:team_builder)
end

# Displays the team editing interface
#
# @see Model#team_create
# @see Model#fetch_team
get('/teams/edit') do
  user_id = session[:user_id]
  team_create(user_id)
  @team = fetch_team(user_id)
  @pokemons = pokedex()
  slim(:update_team)
end

# Updates the user's Pokémon team
#
# @param [Integer] pokemon1 First team member ID
# @param [Integer] pokemon2 Second team member ID
# @param [Integer] pokemon3 Third team member ID
# @param [Integer] pokemon4 Fourth team member ID
# @param [Integer] pokemon5 Fifth team member ID
# @param [Integer] pokemon6 Sixth team member ID
# @see Model#update_team
put('/teams') do
  user_id = session[:user_id]
  update_team(
    params[:pokemon1],
    params[:pokemon2],
    params[:pokemon3],
    params[:pokemon4],
    params[:pokemon5],
    params[:pokemon6]
  )
  redirect('/teams')
end

# ---------------------------------------
# ADMIN ROUTES
# ---------------------------------------

# Displays admin interface with all users
#
# @see Model#fetch_all_users
get('/admin') do
  halt 403, "Access Denied" unless @is_admin
  @users = fetch_all_users()
  slim(:administration)
end

# Deletes a user account
#
# @param [String] username Username to delete
# @see Model#fetch_user_by_username
# @see Model#team_delete
delete('/users/:username') do
  halt 403, "Access Denied" unless @is_admin
  username = params[:username]
  delete_user_by_username(username)
  redirect '/admin'
end

# Updates a Pokémon's stats
#
# @param [String] name Pokémon name
# @param [Integer] hp Hit points
# @param [Integer] attack Attack stat
# @param [Integer] defense Defense stat
# @param [Integer] sp_attack Special attack stat
# @param [Integer] sp_defense Special defense stat
# @param [Integer] speed Speed stat
# @see Model#update_pokemon_stats
put('/pokemons/:name') do
  halt 403, "Access Denied" unless @is_admin
  update_pokemon_stats(
    params[:name],
    params[:hp],
    params[:attack],
    params[:defense],
    params[:sp_attack],
    params[:sp_defense],
    params[:speed]
  )
  redirect("/pokemons/#{params[:name]}")
end