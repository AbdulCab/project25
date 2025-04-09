require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require 'json'
require_relative './model.rb'

enable :sessions


# Database connection method

before do
  @is_admin = session[:role] == "admin"
end


get('/') do
  slim(:index)
end

get('/index') do
  @pokemons = pokedex()

  slim(:index)
end

get('/index/:name') do
  puts "Session Role: #{session[:role]}"  # Check if it's correctly set
  @pokemon = pokedata(:name)
  @pokemon["image_url"]= pokeimg(:name)
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



# kod som är till för js-skripten
get ('/search_pokemon') do
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


get('/register') do
  slim(:register)
end

post('/users/new') do
  username = params[:username]
  password = params[:password]
  password_confirm = params[:password_confirm]

  new_acc_auth(username, password, password_confirm)

end

get('/login')  do
  slim(:login)
end

post('/users/login') do
  username = params[:username]
  password = params[:password]
  halt 400, "Username or password missing" if username.nil? || password.nil?

  result = curr_acc_auth(username, password, session)

  redirect('/index') if result == "Inloggning lyckades"
  result # Returnerar felmeddelandet om inloggningen misslyckas
end

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


get('/logout') do
  session.clear
  redirect('/index')
end
