require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require 'json'
require_relative './model.rb'

include Model

enable :sessions

# Helper method to check if the current user is an admin
before do
  @is_admin = session[:role] == "admin"
  protected_routes_user = ['/teams', '/teams/edit']
  if protected_routes_user.include?(request.path_info) && session[:user_id].nil?
    session[:error] = "Du måste vara inloggad för att komma åt denna sida."
    redirect '/login'
  end
  protected_routes_admin = ['/pokemons/:name/edit', '/admin']
  if protected_routes_admin.include?(request.path_info) && !@is_admin
    session[:error] = "Endast administratörer har åtkomst till denna sida."
    redirect '/pokemons'
  end
end

# Root route
get('/') do
  slim(:index)
end

# List all Pokémon
get('/pokemons') do
  @pokemons = pokedex()
  puts @pokemons.inspect
  slim(:index)
end

# Show details for a specific Pokémon
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

# Search Pokémon
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

# Show registration form
get('/users/register') do
  slim(:register)
end

# Create a new user
post('/users') do
  username = params[:username]
  password = params[:password]
  password_confirm = params[:password_confirm]
  result = new_acc_auth(username, password, password_confirm)
  if result.nil?
    redirect('/login')
  else
    @error = result
    slim(:register)
  end
end

# Login form
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

# Authenticate user
post('/login') do
  username = params[:username]
  password = params[:password]
  session[:login_attempts] ||= 0
  session[:first_attempt_time] ||= Time.now

  if session[:login_attempts] >= 5 && Time.now - session[:first_attempt_time] < 30
    session[:last_login_attempt] = Time.now unless session[:last_login_attempt]
    redirect '/login'
  end

  if Time.now - session[:first_attempt_time] >= 30
    session[:login_attempts] = 0
    session[:first_attempt_time] = Time.now
  end

  if username.nil? || username.empty? || password.nil? || password.empty?
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

# Admin dashboard
get('/admin') do
  halt 403, "Access Denied" unless @is_admin
  @users = fetch_all_users()
  slim(:administration)
end

# Delete a user
delete('/users/:username') do
  halt 403, "Access Denied" unless @is_admin
  username = params[:username]
  user = fetch_user_by_username(username)
  if user
    user_id = user["id"]
    team_delete(user_id)
    delete_user_by_username(username)
  end
  redirect '/admin'
end

# Edit Pokémon stats
put('/pokemons/:name') do
  halt 403, "Access Denied" unless @is_admin
  name = params[:name]
  hp = params[:hp]
  attack = params[:attack]
  defense = params[:defense]
  sp_attack = params[:sp_attack]
  sp_defense = params[:sp_defense]
  speed = params[:speed]
  update_pokemon_stats(name, hp, attack, defense, sp_attack, sp_defense, speed)
  redirect("/pokemons/#{name}")
end

# Show team builder
get('/teams') do
  user_id = session[:user_id]
  halt 403, "Du måste vara inloggad för att komma åt denna sida." unless user_id
  team = fetch_team(user_id)
  @pokemons = team ? fetch_team_pokemon_data(team) : []
  slim(:team_builder)
end

# Edit team
get('/teams/edit') do
  user_id = session[:user_id]
  halt 403, "Du måste vara inloggad för att komma åt denna sida." unless user_id
  team_create(user_id)
  @team = fetch_team(user_id)
  @pokemons = pokedex()
  slim(:update_team)
end

# Update team
put('/teams') do
  user_id = session[:user_id]
  halt 403, "Du måste vara inloggad för att uppdatera ditt team." unless user_id
  pokemon1 = params[:pokemon1]
  pokemon2 = params[:pokemon2]
  pokemon3 = params[:pokemon3]
  pokemon4 = params[:pokemon4]
  pokemon5 = params[:pokemon5]
  pokemon6 = params[:pokemon6]
  update_team(pokemon1, pokemon2, pokemon3, pokemon4, pokemon5, pokemon6)
  redirect('/teams')
end

# Logout
get('/logout') do
  session.clear
  session[:error] = "Du har loggats ut."
  redirect('/pokemons')
end