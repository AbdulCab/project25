require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require 'json'
require_relative './model.rb'

enable :sessions


# Database connection method


get('/') do
  slim(:index)
end

get('/index') do
  @pokemons = pokedex()

  slim(:index)
end

get('/index/:name') do

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


post('/login') do 
  username = params[:username]
  password = params[:password]
  db = SQLite3::Database.new('db/pokemon.db')
  db.results_as_hash = true
  result = db.execute("SELECT * FROM users WHERE username = ?",username).first
  pwdigest = result["pwdigest"]
  id = result["id"]

  if BCrypt::Password.new(pwdigest) == password
    session[:id] = id
    
    redirect('/index')
  else
    "Fel lösen"
  end
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
  puts "Received params: #{params.inspect}" # Debugging
  halt 400, "Username or password missing" if username.nil? || password.nil?
  curr_acc_auth(username, password, session)
end

