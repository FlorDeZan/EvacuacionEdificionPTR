model MapLayers

import"NavNode.gaml"
import "EvacuationExperiment.gaml"

//////////////////////////////////////////////////////
// 1) CAPAS ESTÁTICAS IMPORTADAS DEL EDIFICIO       //
//////////////////////////////////////////////////////

species WalkArea {
	geometry shape;
	
	list<DoorSeg> doors <- [];
	list<DoorSeg> exits <- [];
    int    floor;         // 0 = PB, 1 = piso superior
    string room_id;
    string category;
	
    
    aspect default {
        draw shape
            color: rgb("lightyellow")
            border: #black;
    }
    
    init{
    	doors <- DoorSeg where (each.from_id = room_id and each.floor = floor); // puertas conectadas
	    exits <- ExitSeg where (each.from_id = room_id and each.floor = floor); // salidas conectadas
    }
}

species StairArea parent: WalkArea {
	int capacidad <- MAX_STAIR_CAP;
	list<Person> en_espera <- [];
	list<Person> on_stair <- [];
	list<float> remaining_time <- [];

    string stair_id;
    string id;

    aspect default { draw shape color: rgb("lightblue") border: #navy; }

    reflex procesarFila {
    // 1) Fill staircase from queue (FIFO) up to capacity
    int libres <- capacidad - length(on_stair);

    loop i from: 1 to: libres {
        if (length(en_espera) = 0) { break; }

        Person p <- first(en_espera);
        write "🔵 StairArea " + id + " procesando persona " + p.name + " de la cola";

        en_espera <- en_espera - p;
        on_stair <- on_stair + p;
        remaining_time <- remaining_time + DESCENT_TIME;

        ask p {
            do start_using_stair(myself, DESCENT_TIME);
        }
    }

    // 2) Decrement timers for those on the stairs
    if (length(on_stair) > 0) {
        loop idx from: 0 to: (length(on_stair) - 1) {
            remaining_time[idx] <- remaining_time[idx] - step;
        }

        // 3) Release finished people by building new lists
        list<Person> new_on_stair <- [];
        list<float> new_times <- [];
        
        loop idx from: 0 to: (length(on_stair) - 1) {
            if (remaining_time[idx] <= 0.0) {
                // Person finished descending
                Person finished <- on_stair[idx];
                write "✅ StairArea " + id + " liberando persona " + finished.name;
                
                ask finished {
                    do finish_using_stair(myself);
                }
            } else {
                // Still descending - keep in lists
                new_on_stair <- new_on_stair + on_stair[idx];
                new_times <- new_times + remaining_time[idx];
            }
        }
        
        // Update lists atomically
        on_stair <- new_on_stair;
        remaining_time <- new_times;
    }
}}
species DoorSeg {
	NavNode node;
    int floor;
    string to_id;
    string from_id;
    aspect default { draw shape color: rgb("gold") border: #black; }
    
    aspect resaltado {draw shape color: #blue border: #red;}
}

species ExitSeg parent: DoorSeg {
    string exit_id;
    
    aspect default { draw shape color: rgb("red") border: #black; }
}

species WallPoly {
    int floor;
    aspect default { draw shape color: rgb("saddlebrown") border: #black; }
}