model Person
import "MapLayers.gaml"
import "EvacuationExperiment.gaml"

species Person skills:[moving] {
	// ============================================
    // ATRIBUTOS BÁSICOS
    // ============================================
	int origin_floor;
	int floor;
	WalkArea current_area;
	DoorSeg current_objective;
	graph current_graph;
	float personal_space <- 0.3;
	float repulsion_strength <- 0.2;
	StairArea current_stair_waiting_for <- nil;
	string origin_room <- nil; 
	// ============================================
    // VELOCIDAD CON MULTIPLICADORES
    // ============================================
    float base_speed <- rnd(1.0, 1.5);
    float speed_multiplier <- 1.0;
    float speed <- base_speed * speed_multiplier update: base_speed * speed_multiplier;

    float SPEED_REPOSO <- 0.0;
    float SPEED_CALMADO <- 0.9;
    float SPEED_ALTERADO <- 1.3;
    float SPEED_PANICO <- 1.6;
    float SPEED_PARALIZADO <- 0.1;
    
	// ============================================
    // MÁQUINA DE ESTADOS
    // ============================================
    string behavioral_state <- "reposo";
    bool escucho_alarma <- false;
    bool camino_obstruido <- false;
    bool esperando_escalera <- false;
    string estado_antes_de_cola <- nil;  // Guardar estado antes de entrar a la cola
    
    int forma_evacuacion <- -1;

    point last_position;
    float stuck_time <- 0.0;
    float STUCK_THRESHOLD <- 3.0;
    
	// ============================================
    // ASPECTO VISUAL
    // ============================================
    aspect default {
        rgb color_by_state;
        
        switch behavioral_state {
            match "reposo" { color_by_state <- rgb(70,130,180); }
            match "alerta" { color_by_state <- rgb(255,165,0); }
            match "evacuando_calmado" { color_by_state <- rgb(50,205,50); }
            match "evacuando_alterado" { color_by_state <- rgb(255,140,0); }
            match "panico" { color_by_state <- rgb(220,20,60); }
            match "paralizado" { color_by_state <- rgb(138,43,226); }
            match "atascado" { color_by_state <- rgb(218,165,32); }
            match "usando_escalera" { color_by_state <- rgb(100,149,237); }
            match "a_salvo" { color_by_state <- rgb(211,211,211); }
            default { color_by_state <- rgb(128,128,128); }
        }

        draw circle(0.45) color: color_by_state border: #black;
    }

	action CalculateCurrentLocation {
        if (current_area != nil) {
            location <- any_location_in(current_area.shape);
            last_position <- location;
        }
    }

	action CalculateCurrentArea {
        current_area <- one_of(WalkArea where (each.floor = floor and each.shape covers self.location));
        
        if (current_area = nil) {
        	current_area <- one_of(StairArea where (each.floor = floor and each.shape covers self.location));
        }
    }

	action CalculateCurrentAreaGraph {
		if (current_area != nil and current_area.category = "corridor") {
			current_graph <- graphs at floor;
		}
		else {
			current_graph <- nil;
		}
	}

	action SetCurrentObjective {
		current_objective <- nil;
		list<DoorSeg> potential_objetives <- [];

        // Preferir exits si existen
        if (current_area.exits != nil and length(current_area.exits) > 0) {
            potential_objetives <- current_area.exits;
        } else if (current_area.doors != nil and length(current_area.doors) > 0) {
            potential_objetives <- current_area.doors;
        }

        // Si no hay candidatos, salir
        if (length(potential_objetives) = 0) { 
        	camino_obstruido <- true;
        	return;
        }

        float min_distance_ <- #max_float;
        loop door over: potential_objetives {
            float dist <- self distance_to(door.location);
            if (dist < min_distance_) {
                min_distance_ <- dist;
                current_objective <- door;
            }
        }
    }
    
    action intentar_usar_escalera (StairArea s) {
    	if (!(self in s.en_espera) and not esperando_escalera) {
    		// Guardar el estado actual antes de entrar a la cola
    		estado_antes_de_cola <- behavioral_state;
    		
        	s.en_espera <- s.en_espera + self;
	        esperando_escalera <- true;
	        current_stair_waiting_for <- s;
	        speed_multiplier <- 0.0;
	        
	        // Cambiar a estado atascado porque está en cola
	        behavioral_state <- "atascado";
	        camino_obstruido <- true;
	        
	        tiempo_entrada_cola[self] <- time;
    	}
	}
	
	action start_using_stair (StairArea s, float duration) {
	    esperando_escalera <- false;
	    current_stair_waiting_for <- nil;
	    behavioral_state <- "usando_escalera";
	    speed_multiplier <- 0.0;
	    camino_obstruido <- false;
	   // NUEVO: Registrar uso de escalera
	world.personas_por_escalera[s.id] <- world.personas_por_escalera[s.id] + 1;
	
	// Calcular tiempo en cola
	if (world.tiempo_entrada_cola[self] != nil) {
		float tiempo_cola <- time - world.tiempo_entrada_cola[self];
		world.tiempos_cola_escalera[s.id] <- world.tiempos_cola_escalera[s.id] + tiempo_cola;
		world.tiempo_entrada_cola[self] <- nil;
	}
	}
	
	action finish_using_stair (StairArea s) {
	    if s = nil {
    		write "ERROR: finish_using_stair recibió una stair nil en " + name;
    		return;
		}
	    
	    // Bajar un piso
	    floor <- floor - 1;
	    write "🔽 " + name + " bajó al piso " + floor;
	    
	    // Buscar el área de aterrizaje en el nuevo piso
	    StairArea landing <- first(StairArea where (each.id = s.id and each.floor = floor));
	    
	    if (landing != nil) {
	        location <- any_location_in(landing.shape);
	        write "  → Ubicación actualizada en escalera " + landing.id;
	    } else {
	        write "  ⚠️ WARNING: No se encontró landing para escalera " + s.id + " en piso " + floor;
	    }
	
	    // Restaurar estado previo a la cola (si existe) o usar evacuando_calmado por defecto
	    if (estado_antes_de_cola != nil and estado_antes_de_cola in ["evacuando_calmado", "evacuando_alterado", "panico"]) {
	        behavioral_state <- estado_antes_de_cola;
	        
	        // Restaurar velocidad según el estado
	        if (estado_antes_de_cola = "evacuando_calmado") {
	            speed_multiplier <- SPEED_CALMADO;
	        } else if (estado_antes_de_cola = "evacuando_alterado") {
	            speed_multiplier <- SPEED_ALTERADO;
	        } else if (estado_antes_de_cola = "panico") {
	            speed_multiplier <- SPEED_PANICO;
	        }
	        
	        write "  → Estado restaurado: " + behavioral_state;
	    } else {
	        behavioral_state <- "evacuando_calmado";
	        speed_multiplier <- SPEED_CALMADO;
	        write "  → Estado por defecto: evacuando_calmado";
	    }
	    
	    estado_antes_de_cola <- nil;
	    last_position <- location;
	    stuck_time <- 0.0;
	    camino_obstruido <- false;
	
	    // Recalcular área, grafo y objetivo
	    do CalculateCurrentArea;
	    write "  → Current area después de bajar: " + 
	          (current_area != nil ? (current_area.room_id + " (categoría: " + current_area.category + ")") : "nil");
	    
	    do CalculateCurrentAreaGraph;
	    write "  → Grafo asignado: " + (current_graph != nil ? "Sí" : "No");
	    
	    do SetCurrentObjective;
	    write "  → Nuevo objetivo: " + 
	          (current_objective != nil ? current_objective.to_id : "nil");
	}
    
    // ============================================
    // ESTADOS COMPORTAMENTALES
    // ============================================
    action ReposoState {
        behavioral_state <- "reposo";
        speed_multiplier <- SPEED_REPOSO;
    }
    
    action AlertaState {
        behavioral_state <- "alerta";
        speed_multiplier <- SPEED_ALTERADO;
        escucho_alarma <- true;
        if (current_objective = nil) {
            do SetCurrentObjective;
        }
    }
    
    action EvacuandoCalmadoState {
        behavioral_state <- "evacuando_calmado";
        speed_multiplier <- SPEED_CALMADO;
        forma_evacuacion <- 2;
    }
    
    action EvacuandoAlteradoState {
        behavioral_state <- "evacuando_alterado";
        speed_multiplier <- SPEED_ALTERADO;
        forma_evacuacion <- 1;
    }

    action PanicoState {
        behavioral_state <- "panico";
        speed_multiplier <- SPEED_PANICO;
        forma_evacuacion <- 4;
//        if (flip(0.8)) {
//            do SetCurrentObjective;
//        }

    }

    action ParalizadoState {
        behavioral_state <- "paralizado";
        speed_multiplier <- SPEED_PARALIZADO;
        forma_evacuacion <- 3;
    }

    action AtascadoState {
        behavioral_state <- "atascado";
        speed_multiplier <- SPEED_PARALIZADO;
        camino_obstruido <- true;
        do SetCurrentObjective;
    }

    action ASalvoState {
        behavioral_state <- "a_salvo";
        speed_multiplier <- 0.0;
    }
    
    // ============================================
    // FUNCIÓN: FormaEvacuacion
    // ============================================
    action FormaEvacuacion {
        int r <- rnd(0, 100);
        
        if (r <= 40) {
            do EvacuandoAlteradoState;
        } 
        else if (r <= 80) {
            do EvacuandoCalmadoState;
        }
        else if (r <= 90) {
            do PanicoState;
        }
        else {
            do ParalizadoState;
        }
    }
    
    // ============================================
    // DETECCIÓN DE OBSTRUCCIÓN
    // ============================================
    action CheckObstruction {
        if (last_position = nil) {
            last_position <- location;
            return;
        }
        
        float distance_moved <- location distance_to(last_position);

        if (distance_moved < 0.02 and behavioral_state in ["evacuando_calmado", "evacuando_alterado"]) {
            stuck_time <- stuck_time + step;
            if (stuck_time >= STUCK_THRESHOLD) {
                camino_obstruido <- true;
            }
        } else {
            stuck_time <- 0.0;
            camino_obstruido <- false;
        }
        last_position <- location;
    }
    
    // ============================================
    // TRANSICIONES DE ESTADOS
    // ============================================
    reflex state_machine when: behavioral_state != "a_salvo" and behavioral_state != "usando_escalera" and not esperando_escalera {
        
        if (behavioral_state = "reposo") {
            if (escucho_alarma) {
                do AlertaState;
            }
        }
        else if (behavioral_state = "alerta") {
            do FormaEvacuacion;
        }
        else if (behavioral_state = "evacuando_calmado") {
            if (camino_obstruido) {
                do AtascadoState;
            }
        }
        else if (behavioral_state = "evacuando_alterado") {
            if (camino_obstruido and forma_evacuacion = 1) {
                do AtascadoState;
            }
        }
        else if (behavioral_state = "paralizado") {
            if (flip(0.1)) {
                do FormaEvacuacion;
            }
        }
        else if (behavioral_state = "panico") {
            if (camino_obstruido and forma_evacuacion = 4) {
                do AtascadoState;
            }
            else if (flip(0.05)) {
                do FormaEvacuacion;
            }
        }
        else if (behavioral_state = "atascado") {
            if (not camino_obstruido and forma_evacuacion = 2) {
                do EvacuandoCalmadoState;
            }
            else if (not camino_obstruido and forma_evacuacion = 1) {
                do EvacuandoAlteradoState;
            }
            else if (camino_obstruido and forma_evacuacion = 4) {
                do PanicoState;
            }
            if (stuck_time > 10.0) {
                do FormaEvacuacion;
            }
        }

        do CheckObstruction;
    }
    
    // ============================================
    // MOVIMIENTO Y NAVEGACIÓN
    // ============================================
    reflex moversePanico when: behavioral_state = "panico"{
		do wander speed: speed bounds: current_area - 0.5 amplitude: 0.5;
    }
    
    reflex salir when: not (behavioral_state in ["reposo", "a_salvo", "usando_escalera", "panico"]) 
    			 	   and not esperando_escalera and current_objective != nil {
		if (speed_multiplier > 0.0) {
            if (current_graph != nil){
                do goto target: current_objective.location speed: speed on: current_graph;
            }
            else {
                do goto target: current_objective.location speed: speed;
            }
		}
        
	        // Evaluar si llegó al objetivo
	        if (self distance_to(current_objective.location) < 0.5) {
	            
	            // Si es una salida final (sin to_id), la persona está a salvo
				if (current_objective.to_id = nil) {
					write "✅ " + name + " ha salido del edificio (a salvo)";
		
				// NUEVO: Registrar métricas de evacuación
				if (world.tiempo_inicio_persona[self] != nil) {
					float tiempo_evacuacion <- time - world.tiempo_inicio_persona[self];
					world.tiempos_individuales <- world.tiempos_individuales + tiempo_evacuacion;
					world.tiempos_por_piso[origin_floor] <- world.tiempos_por_piso[origin_floor] + tiempo_evacuacion;
				}
		
				// Registrar salida usada
				ExitSeg salida_usada <- one_of(ExitSeg where (each.location distance_to(current_objective.location) < 0.5));
				if (salida_usada != nil) {
					world.personas_por_salida[salida_usada.exit_id] <- world.personas_por_salida[salida_usada.exit_id] + 1;
				}
		
				// Contar evacuados por piso
				world.evacuados_por_piso[origin_floor] <- world.evacuados_por_piso[origin_floor] + 1;
		
				// Contar evacuados por aula
				if (origin_room != nil) {
					string aula_key <- origin_room + "_P" + origin_floor;
					world.evacuados_por_aula[aula_key] <- world.evacuados_por_aula[aula_key] + 1;
				}
		
				// Contar si estuvo atascado
				if (world.tiempo_atascado[self] > 0) {
					world.total_atascados <- world.total_atascados + 1;
				}
		
				current_objective <- nil;
				do ASalvoState;
				do die;
			}
	        else {
	            string next_room_id <- current_objective.to_id;
	            write "🚪 " + name + " atravesó puerta hacia: " + next_room_id + " (piso " + floor + ")";
	            
	            // Si el siguiente destino es una escalera
	            if (next_room_id in ["S1", "S2", "S3"]) {
	                // Buscar la StairArea correspondiente en el piso actual
	                StairArea target_stair <- first(StairArea where (
	                    each.id = next_room_id and 
	                    each.floor = floor
	                ));
	                
	                if (target_stair != nil) {
	                    write "🪜 " + name + " se une a la cola de escalera " + next_room_id;
	                    // Unirse a la cola de la escalera
	                    do intentar_usar_escalera(target_stair);
	                } else {
	                    write "❌ ERROR: No se encontró StairArea " + next_room_id + " en piso " + floor;
	                }
	            }
	            else {
	                // Movimiento dentro del mismo piso - BUSCAR WALKAREA EN EL PISO ACTUAL
	                current_area <- one_of(WalkArea where (
	                    each.room_id = next_room_id and 
	                    each.floor = floor
	                ));
	                
	                if (current_area != nil) {
	                    write "✓ " + name + " entró al área " + current_area.room_id + " (categoría: " + current_area.category + ")";
	                    
	                    // Actualizar grafo si es corredor
	                    if (current_area.category = "corridor") {
	                        current_graph <- graphs at floor;
	                        write "  → Usando grafo del piso " + floor;
	                    } else {
	                        current_graph <- nil;
	                    }
	                    
	                    // Buscar nuevo objetivo
	                    do SetCurrentObjective;
	                    
	                    if (current_objective != nil) {
	                        write "  → Nuevo objetivo: " + current_objective.to_id;
	                    } else {
	                        write "  ⚠️ No se encontró nuevo objetivo";
	                    }
	                } 
	                else {
	                    write "❌ ERROR: No se encontró WalkArea '" + next_room_id + "' en piso " + floor;
	                    write "   Áreas disponibles en piso " + floor + ": " + 
	                          (WalkArea where (each.floor = floor)) collect each.room_id;
	                }
				}
	        }	
	    }
	}
	
	reflex avoid_collisions when: behavioral_state != "usando_escalera" and not esperando_escalera {
	    list<Person> near_people <- Person where (each != self and self distance_to each < personal_space);
	
	    if (length(near_people) > 0) {
	        point push <- {0,0};
	
	        loop p over: near_people {
	            point direction <- (self.location - p.location);
	            float dist <- direction distance_to({0,0}) max 0.001;
	            point unit <- direction / dist;
	            push <- push + (unit / (dist * dist));
	        }
	
	        float m <- push distance_to({0,0});
	        if (m > 0) {
	            push <- (push / m) * repulsion_strength;
	        }
	
	        location <- location + push;
	    }
	}
}