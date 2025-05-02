document.addEventListener("DOMContentLoaded", function () {
  let searchBox = document.getElementById("search-box");
  let resultsList = document.getElementById("search-results");

  searchBox.addEventListener("input", function () {
    let query = searchBox.value.trim();
    
    if (query.length > 0) {
      fetch(`/search_pokemon?q=${encodeURIComponent(query)}`)
        .then(response => response.json())
        .then(data => {
          resultsList.innerHTML = ""; // Clear previous results

          if (data.length === 0) {
            let noResults = document.createElement("li");
            noResults.textContent = "No Pokémon found.";
            resultsList.appendChild(noResults);
            resultsList.classList.add("active"); // Show dropdown when no results
            return;
          }

          data.forEach(pokemon => {
            let li = document.createElement("li");
            li.classList.add("search-result-item");

            let link = document.createElement("a");
            link.href = `/pokemons/${pokemon.name}`;
            link.textContent = pokemon.name;

            let img = document.createElement("img");
            img.src = pokemon.image_url || "https://via.placeholder.com/50";
            img.alt = pokemon.name;
            img.classList.add("search-img");

            let typeSpan = document.createElement("span");
            typeSpan.textContent = pokemon.types ? `(${pokemon.types})` : "";
            typeSpan.classList.add("search-type");

            li.appendChild(img);
            li.appendChild(link);
            li.appendChild(typeSpan);
            resultsList.appendChild(li);
          });

          resultsList.classList.add("active"); // Show the dropdown with results
        })
        .catch(error => console.error("Error fetching Pokémon:", error));
    } else {
      resultsList.innerHTML = ""; // Clear results if input is empty
      resultsList.classList.remove("active"); // Hide the dropdown
    }
  });
});
