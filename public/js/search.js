document.addEventListener("DOMContentLoaded", function () {
    let searchBox = document.getElementById("search-box");
    let resultsList = document.getElementById("search-results");
  
    if (searchBox) {
      searchBox.addEventListener("input", function () {
        let query = searchBox.value.trim();
        console.log("Searching for:", query);
  
        if (query.length > 0) {
          fetch(`/search_pokemon?q=${encodeURIComponent(query)}`)
            .then(response => response.json())
            .then(data => {
              console.log("Received data:", data); // Debugging line
              resultsList.innerHTML = ""; // Clear previous results
  
              data.forEach(pokemon => {
                let li = document.createElement("li");
                let link = document.createElement("a");
                let img = document.createElement("img");
                let typeSpan = document.createElement("span");
  
                link.href = `/pokedex/${pokemon.name}`;
                link.textContent = pokemon.name;
  
                img.src = pokemon.image_url;
                img.alt = pokemon.name;
                img.classList.add("search-img");
  
                typeSpan.textContent = `(${pokemon.types})`;
                typeSpan.classList.add("search-type");
  
                li.appendChild(img);
                li.appendChild(link);
                li.appendChild(typeSpan);
                resultsList.appendChild(li);
              });
            })
            .catch(error => console.error("Error fetching Pokémon:", error));
        } else {
          resultsList.innerHTML = ""; // Clear results if input is empty
        }
      });
    }
  });
  