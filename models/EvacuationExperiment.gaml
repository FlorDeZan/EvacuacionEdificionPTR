model EvacuationExperiment

import "MapLayers.gaml"
import "Person.gaml"
import "NavNode.gaml"

global {
	//VARIABLES GLOBALES DE ESCALERAS
	int MAX_STAIR_CAP <- 3;
	float DESCENT_TIME <- 12.0;
	
	//VARIABLES GLOBALES DE NODOS Y GRAFICOS
	bool SHOW_NODES <- true;
	int NODES_PER_CORRIDOR <- 200;
	float max_distance <- 2.0;
	float min_distance <- 1.0;
	map<int, graph> graphs;
	
	//VARIABLES GLOBALES DE PISOS
	int TOTAL_FLOORS <- 2;
	
	// ============================================
	// PARÁMETROS CONFIGURABLES POR AULA - PISO 0
	// ============================================
	int P0_Aula01 <- 5;
	int P0_Aula02 <- 8;
	int P0_Aula03 <- 0;
	int P0_Aula04 <- 12;
	int P0_Aula05 <- 0;
	int P0_Aula06 <- 10;
	int P0_Aula07 <- 7;
	int P0_Aula08 <- 0;
	int P0_Aula09 <- 6;
	int P0_Aula10 <- 9;
	int P0_Aula11 <- 3;
	
	// ============================================
	// PARÁMETROS CONFIGURABLES POR AULA - PISO 1
	// ============================================
	int P1_Aula01 <- 15;
	int P1_Aula02 <- 12;
	int P1_Aula03 <- 8;
	int P1_Aula04 <- 0;
	int P1_Aula05 <- 10;
	int P1_Aula06 <- 0;
	int P1_Aula07 <- 11;
	int P1_Aula08 <- 9;
	int P1_Aula09 <- 7;
	int P1_Aula10 <- 0;
	int P1_Aula11 <- 4;
	
	// Mapas internos (se crean automáticamente)
	map<string, int> personas_piso0;
	map<string, int> personas_piso1;
	
	// Totales calculados automáticamente
	int N_floor0;
	int N_floor1;
	
	// CONTROL DE ALARMA GLOBAL
    bool alarm_active <- false;
    float alarm_start_time <- 5.0;
    
    // ============================================
    // MÉTRICAS SIMPLES
    // ============================================
    
    // Tiempos de evacuación
    float tiempo_inicio_evacuacion <- -1.0;
    map<Person, float> tiempo_inicio_persona <- map([]);
    list<float> tiempos_individuales <- [];
    map<int, list<float>> tiempos_por_piso <- map([0::[], 1::[]]);
    
    // Flujo por escaleras y salidas
    map<string, int> personas_por_escalera <- map([]);
    map<string, int> personas_por_salida <- map([]);
    
    // Tiempos en colas
    map<Person, float> tiempo_entrada_cola <- map([]);
    map<string, list<float>> tiempos_cola_escalera <- map([]);
    
    // Congestión
    map<Person, float> tiempo_atascado <- map([]);
    int total_atascados <- 0;
    
    // Evacuados por piso y por aula
    map<int, int> evacuados_por_piso <- map([0::0, 1::0]);
    map<string, int> evacuados_por_aula <- map([]);
	
	init {
		// Construir mapas desde parámetros
		personas_piso0 <- [
			"Aula01"::P0_Aula01,
			"Aula02"::P0_Aula02,
			"Aula03"::P0_Aula03,
			"Aula04"::P0_Aula04,
			"Aula05"::P0_Aula05,
			"Aula06"::P0_Aula06,
			"Aula07"::P0_Aula07,
			"Aula08"::P0_Aula08,
			"Aula09"::P0_Aula09,
			"Aula10"::P0_Aula10,
			"Aula11"::P0_Aula11
		];
		
		personas_piso1 <- [
			"Aula01"::P1_Aula01,
			"Aula02"::P1_Aula02,
			"Aula03"::P1_Aula03,
			"Aula04"::P1_Aula04,
			"Aula05"::P1_Aula05,
			"Aula06"::P1_Aula06,
			"Aula07"::P1_Aula07,
			"Aula08"::P1_Aula08,
			"Aula09"::P1_Aula09,
			"Aula10"::P1_Aula10,
			"Aula11"::P1_Aula11
		];
		
		// Calcular totales
		N_floor0 <- sum(personas_piso0.values);
		N_floor1 <- sum(personas_piso1.values);
		
        // ====== CARGAR CAPAS ======
        create WalkArea  from: file("walkable_shifted.geojson");
        create StairArea from: file("stair_shifted.geojson");
        create DoorSeg   from: file("door_shifted.geojson");
        create ExitSeg   from: file("exit_shifted.geojson");
        create WallPoly  from: file("wall_shifted.geojson");
        
        // Inicializar métricas de escaleras
        ask StairArea {
        	personas_por_escalera[id] <- 0;
        	tiempos_cola_escalera[id] <- [];
        }
        
        // Inicializar métricas de salidas
        ask ExitSeg {
        	personas_por_salida[exit_id] <- 0;
        }
        
        // Inicializar contadores por aula
        loop aula_id over: personas_piso0.keys {
        	evacuados_por_aula[aula_id + "_P0"] <- 0;
        }
        loop aula_id over: personas_piso1.keys {
        	evacuados_por_aula[aula_id + "_P1"] <- 0;
        }
        
        // ====== CREAR NODOS DE NAVEGACIÓN ======
		list<WalkArea> corridors <- WalkArea where (each.category = "corridor");
		loop corridor over: corridors {
			int created <- 0;
    		int attempts <- 0;
    		int max_attempts <- NODES_PER_CORRIDOR * 20;
    		
    		loop while: (created < NODES_PER_CORRIDOR and attempts < max_attempts) {
    			attempts <- attempts + 1;
    			point p <- any_location_in(corridor.shape);
    			
    			if (NavNode count(each distance_to(p) < min_distance) = 0) {
    				create NavNode {
                		floor <- corridor.floor;
                		location <- p;
            		}
            		created <- created + 1;
    			}
    		}
		}
		
		ask DoorSeg {
			create NavNode returns: node_r {
                floor <- myself.floor;
                location <- myself.location;
            }
            self.node <- one_of(node_r);
		} 
		
		ask ExitSeg{
			create NavNode returns: node_r {
                floor <- myself.floor;
                location <- myself.location;
            }
            self.node <- one_of(node_r);
		}
		
		ask NavNode {
			list<NavNode> nearby <- NavNode where (each != self and each.floor = self.floor and self distance_to(each.location) <= max_distance);
			neighbors <- list(nearby);
		}
		
		loop f from: 0 to: (TOTAL_FLOORS - 1){
			list<NavNode> nodes_floor <- NavNode where (each.floor = f);
			graphs <- graphs + (f::(nodes_floor as_distance_graph(max_distance)));
		}
		
		// ====== CREAR LISTAS DE SALIDAS Y PUERTAS ======
        ask WalkArea {
            doors <- DoorSeg where (each.from_id = room_id and each.floor = floor);
            exits <- ExitSeg where (each.from_id = room_id and each.floor = floor);
        }
        
        ask StairArea {
            doors <- DoorSeg where (each.from_id = id  and each.floor = floor);
            exits <- ExitSeg where (each.from_id = id and each.floor = floor);
        }
        
        // ====== CREAR PERSONAS EN PISO 0 POR AULA ======
        loop aula_id over: personas_piso0.keys {
        	int cantidad <- personas_piso0[aula_id];
        	
        	if (cantidad > 0) {
        		WalkArea aula <- one_of(WalkArea where (each.floor = 0 and each.room_id = aula_id));
        		
        		if (aula != nil) {
        			create Person number: cantidad {
		                origin_floor <- 0;
		            	floor <- origin_floor;
		            	origin_room <- aula_id;
		                current_area <- aula;
		                do CalculateCurrentLocation;
		                do ReposoState;
		                tiempo_atascado[self] <- 0.0;
		            }
		            write "✅ Creadas " + cantidad + " personas en " + aula_id + " (Piso 0)";
        		} else {
        			write "⚠️ WARNING: No se encontró aula " + aula_id + " en piso 0";
        		}
        	}
        }

        // ====== CREAR PERSONAS EN PISO 1 POR AULA ======
        loop aula_id over: personas_piso1.keys {
        	int cantidad <- personas_piso1[aula_id];
        	
        	if (cantidad > 0) {
        		WalkArea aula <- one_of(WalkArea where (each.floor = 1 and each.room_id = aula_id));
        		
        		if (aula != nil) {
        			create Person number: cantidad {
		                origin_floor <- 1;
		            	floor <- origin_floor;
		            	origin_room <- aula_id;
		                current_area <- aula;
		                do CalculateCurrentLocation;
		                do ReposoState;
		                tiempo_atascado[self] <- 0.0;
		            }
		            write "✅ Creadas " + cantidad + " personas en " + aula_id + " (Piso 1)";
        		} else {
        			write "⚠️ WARNING: No se encontró aula " + aula_id + " en piso 1";
        		}
        	}
        }
        
        write "";
        write "📊 RESUMEN DE POBLACIÓN:";
        write "   Piso 0: " + N_floor0 + " personas";
        write "   Piso 1: " + N_floor1 + " personas";
        write "   TOTAL: " + (N_floor0 + N_floor1) + " personas";
	}
	
	// Activar alarma global
    reflex activate_alarm when: time >= alarm_start_time and not alarm_active {
        alarm_active <- true;
        write "🚨 ¡ALARMA ACTIVADA! t=" + time;
        tiempo_inicio_evacuacion <- time;
        
        ask Person where (each.behavioral_state = "reposo") {
            escucho_alarma <- true;
            tiempo_inicio_persona[self] <- time;
        }
    }
    
    // Actualizar métricas continuamente
    reflex actualizar_metricas {
    	// Registrar tiempo atascado
    	ask Person where (each.behavioral_state = "atascado") {
    		tiempo_atascado[self] <- tiempo_atascado[self] + step;
    	}
    }
    
    // Monitor de estados (cada 5 segundos)
    reflex monitor_states when: mod(cycle, 50) = 0 {
        map<string, int> state_counts <- map([]);
        
        ask Person {
            string s <- behavioral_state;
            int current <- (state_counts[s] != nil) ? state_counts[s] : 0;
            state_counts[s] <- current + 1;
        }
        
        write "📊 [t=" + time + "] Estados: " + state_counts;
    }
    
    // Monitor de colas en escaleras (cada 2 segundos)
    reflex monitor_queues when: mod(cycle, 20) = 0 {
        ask StairArea {
            if (length(en_espera) > 0 or length(on_stair) > 0) {
                write "🪜 Escalera " + id + " (piso " + floor + "): " + 
                      length(en_espera) + " en cola, " + 
                      length(on_stair) + " usando";
            }
        }
    }
    
    // REPORTE FINAL cuando todos evacuaron
    reflex metricas_finales when: length(Person) = 0 and length(tiempos_individuales) > 0 {
    	write "";
    	write "═══════════════════════════════════════════";
    	write "📊 MÉTRICAS FINALES DE EVACUACIÓN";
    	write "═══════════════════════════════════════════";
    	
    	// 1. TIEMPO TOTAL
    	float tiempo_total <- time - tiempo_inicio_evacuacion;
    	write "⏱️ Tiempo total evacuación: " + tiempo_total + " segundos";
    	
    	// 2. TIEMPOS INDIVIDUALES
    	if (length(tiempos_individuales) > 0) {
    		float promedio <- mean(tiempos_individuales);
    		float maximo <- max(tiempos_individuales);
    		float minimo <- min(tiempos_individuales);
    		write "   - Tiempo promedio: " + promedio + "s";
    		write "   - Tiempo máximo: " + maximo + "s";
    		write "   - Tiempo mínimo: " + minimo + "s";
    	}
    	
    	// 3. FLUJO POR ESCALERAS
    	write "";
    	write "🪜 FLUJO POR ESCALERAS:";
    	loop stair_id over: personas_por_escalera.keys {
    		int total <- personas_por_escalera[stair_id];
    		float flujo <- (tiempo_total > 0) ? (total / (tiempo_total / 60.0)) : 0.0;
    		write "   " + stair_id + ": " + total + " personas (" + flujo + " pers/min)";
    		
    		// Tiempos promedio en cola
    		if (length(tiempos_cola_escalera[stair_id]) > 0) {
    			float tiempo_cola_prom <- mean(tiempos_cola_escalera[stair_id]);
    			float tiempo_cola_max <- max(tiempos_cola_escalera[stair_id]);
    			write "      - Tiempo promedio cola: " + tiempo_cola_prom + "s";
    			write "      - Tiempo máximo cola: " + tiempo_cola_max + "s";
    		}
    	}
    	
    	// 4. FLUJO POR SALIDAS
    	write "";
    	write "🚪 FLUJO POR SALIDAS:";
    	loop exit_id over: personas_por_salida.keys {
    		int total <- personas_por_salida[exit_id];
    		float flujo <- (tiempo_total > 0) ? (total / (tiempo_total / 60.0)) : 0.0;
    		write "   " + exit_id + ": " + total + " personas (" + flujo + " pers/min)";
    	}
    	
    	// 5. CONGESTIÓN
    	write "";
    	write "🚧 CONGESTIÓN Y CUELLOS DE BOTELLA:";
    	write "   - Personas atascadas: " + total_atascados;
    	if (total_atascados > 0) {
    		float promedio_atascado <- sum(tiempo_atascado.values) / total_atascados;
    		write "   - Tiempo promedio atascado: " + promedio_atascado + "s";
    	}
    	
    	// 6. DESEMPEÑO POR PISO
    	write "";
    	write "🏢 DESEMPEÑO POR PISO:";
    	loop piso from: 0 to: (TOTAL_FLOORS - 1) {
    		int total_piso <- (piso = 0) ? N_floor0 : N_floor1;
    		int evacuados <- evacuados_por_piso[piso];
    		
    		write "   Piso " + piso + ":";
    		write "      - Total personas: " + total_piso;
    		write "      - Evacuadas: " + evacuados;
    		
    		if (length(tiempos_por_piso[piso]) > 0) {
    			float tiempo_prom_piso <- mean(tiempos_por_piso[piso]);
    			float tiempo_max_piso <- max(tiempos_por_piso[piso]);
    			write "      - Tiempo promedio: " + tiempo_prom_piso + "s";
    			write "      - Tiempo máximo: " + tiempo_max_piso + "s";
    		}
    	}
    	
    	// 7. DESEMPEÑO POR AULA
    	write "";
    	write "🚪 EVACUACIÓN POR AULA:";
    	write "   Piso 0:";
    	loop aula_id over: personas_piso0.keys {
    		int total <- personas_piso0[aula_id];
    		int evac <- evacuados_por_aula[aula_id + "_P0"];
    		if (total > 0) {
    			write "      " + aula_id + ": " + evac + "/" + total;
    		}
    	}
    	write "   Piso 1:";
    	loop aula_id over: personas_piso1.keys {
    		int total <- personas_piso1[aula_id];
    		int evac <- evacuados_por_aula[aula_id + "_P1"];
    		if (total > 0) {
    			write "      " + aula_id + ": " + evac + "/" + total;
    		}
    	}
    	
    	write "═══════════════════════════════════════════";
    	write "";
    	
    	// Solo mostrar una vez
    	tiempos_individuales <- [];
    }
    
    reflex final when: (length(Person) <= 0){
        do pause;
    }
}


experiment simulacion type: gui {
	// PARÁMETROS GENERALES
    parameter "Tiempo alarma (s)" var: alarm_start_time min: 0.0 max: 30.0 category: "Simulación";
    parameter "Capacidad Escaleras" var: MAX_STAIR_CAP min: 1 max: 10 category: "Simulación";
    parameter "Tiempo Descenso (s)" var: DESCENT_TIME min: 2.0 max: 20.0 category: "Simulación";
    parameter "Mostrar nodos" var: SHOW_NODES category: "Visualización";
    
    // PISO 0 - AULAS
    parameter "P0 - Aula 01" var: P0_Aula01 min: 0 max: 50 category: "Piso 0";
    parameter "P0 - Aula 02" var: P0_Aula02 min: 0 max: 50 category: "Piso 0";
    parameter "P0 - Aula 03" var: P0_Aula03 min: 0 max: 50 category: "Piso 0";
    parameter "P0 - Aula 04" var: P0_Aula04 min: 0 max: 50 category: "Piso 0";
    parameter "P0 - Aula 05" var: P0_Aula05 min: 0 max: 50 category: "Piso 0";
    parameter "P0 - Aula 06" var: P0_Aula06 min: 0 max: 50 category: "Piso 0";
    parameter "P0 - Aula 07" var: P0_Aula07 min: 0 max: 50 category: "Piso 0";
    parameter "P0 - Aula 08" var: P0_Aula08 min: 0 max: 50 category: "Piso 0";
    parameter "P0 - Aula 09" var: P0_Aula09 min: 0 max: 50 category: "Piso 0";
    parameter "P0 - Aula 10" var: P0_Aula10 min: 0 max: 50 category: "Piso 0";
    parameter "P0 - Aula 11" var: P0_Aula11 min: 0 max: 50 category: "Piso 0";
    
    // PISO 1 - AULAS
    parameter "P1 - Aula 01" var: P1_Aula01 min: 0 max: 50 category: "Piso 1";
    parameter "P1 - Aula 02" var: P1_Aula02 min: 0 max: 50 category: "Piso 1";
    parameter "P1 - Aula 03" var: P1_Aula03 min: 0 max: 50 category: "Piso 1";
    parameter "P1 - Aula 04" var: P1_Aula04 min: 0 max: 50 category: "Piso 1";
    parameter "P1 - Aula 05" var: P1_Aula05 min: 0 max: 50 category: "Piso 1";
    parameter "P1 - Aula 06" var: P1_Aula06 min: 0 max: 50 category: "Piso 1";
    parameter "P1 - Aula 07" var: P1_Aula07 min: 0 max: 50 category: "Piso 1";
    parameter "P1 - Aula 08" var: P1_Aula08 min: 0 max: 50 category: "Piso 1";
    parameter "P1 - Aula 09" var: P1_Aula09 min: 0 max: 50 category: "Piso 1";
    parameter "P1 - Aula 10" var: P1_Aula10 min: 0 max: 50 category: "Piso 1";
    parameter "P1 - Aula 11" var: P1_Aula11 min: 0 max: 50 category: "Piso 1";
    
    output {
        display mapa {
            species WalkArea aspect: default;
            species StairArea aspect: default;
            species DoorSeg aspect: default;
            species ExitSeg aspect: default;
            species WallPoly aspect: default;
            species Person aspect: default;
            species NavNode aspect: default;
		}
		
		display "Estados" refresh: every(20 #cycles) {
            chart "Distribución de Estados" type: pie {
                data "Reposo" value: length(Person where (each.behavioral_state = "reposo")) color: rgb(70, 130, 180);
                data "Alerta" value: length(Person where (each.behavioral_state = "alerta")) color: rgb(255, 165, 0);
                data "Evacuando Calmado" value: length(Person where (each.behavioral_state = "evacuando_calmado")) color: rgb(50, 205, 50);
                data "Evacuando Alterado" value: length(Person where (each.behavioral_state = "evacuando_alterado")) color: rgb(255, 140, 0);
                data "Pánico" value: length(Person where (each.behavioral_state = "panico")) color: rgb(220, 20, 60);
                data "Paralizado" value: length(Person where (each.behavioral_state = "paralizado")) color: rgb(138, 43, 226);
                data "Atascado" value: length(Person where (each.behavioral_state = "atascado")) color: rgb(218, 165, 32);
                data "Usando Escalera" value: length(Person where (each.behavioral_state = "usando_escalera")) color: rgb(100, 149, 237);
            }
        }
        
        display "Evolución Temporal" refresh: every(10 #cycles) {
            chart "Estados en el Tiempo" type: series {
                data "Reposo" value: length(Person where (each.behavioral_state = "reposo")) color: rgb(70, 130, 180);
                data "Evacuando Calmado" value: length(Person where (each.behavioral_state = "evacuando_calmado")) color: rgb(50, 205, 50);
                data "Evacuando Alterado" value: length(Person where (each.behavioral_state = "evacuando_alterado")) color: rgb(255, 140, 0);
                data "Pánico" value: length(Person where (each.behavioral_state = "panico")) color: rgb(220, 20, 60);
                data "Paralizado" value: length(Person where (each.behavioral_state = "paralizado")) color: rgb(138, 43, 226);
                data "Atascado" value: length(Person where (each.behavioral_state = "atascado")) color: rgb(218, 165, 32);
                data "Usando Escalera" value: length(Person where (each.behavioral_state = "usando_escalera")) color: rgb(100, 149, 237);
            }
        }
        
        display "Colas en Escaleras" refresh: every(10 #cycles) {
            chart "Personas en Colas" type: series {
                data "Total Esperando" value: sum(StairArea collect length(each.en_espera)) color: rgb(255, 140, 0);
                data "Total Usando" value: sum(StairArea collect length(each.on_stair)) color: rgb(100, 149, 237);
            }
        }
        
        display "Flujo Escaleras" refresh: every(20 #cycles) {
            chart "Personas por Escalera" type: histogram {
                loop stair_id over: personas_por_escalera.keys {
                    data stair_id value: personas_por_escalera[stair_id] color: #blue;
                }
            }
        }
        
        display "Evacuados por Piso" refresh: every(20 #cycles){
            chart "Progreso Evacuación" type: series {
                data "Piso 0" value: evacuados_por_piso[0] color: #green;
                data "Piso 1" value: evacuados_por_piso[1] color: #blue;
            }
        }
        
        // MONITORES
        monitor "Tiempo Simulación" value: time;
        monitor "Personas Totales" value: length(Person);
        monitor "Piso 0" value: N_floor0;
        monitor "Piso 1" value: N_floor1;
        monitor "──────────────" value: "";
        monitor "En Reposo" value: length(Person where (each.behavioral_state = "reposo"));
        monitor "Evacuando" value: length(Person where (each.behavioral_state in ["evacuando_calmado", "evacuando_alterado"]));
        monitor "En Pánico" value: length(Person where (each.behavioral_state = "panico"));
        monitor "Paralizados" value: length(Person where (each.behavioral_state = "paralizado"));
        monitor "Atascados" value: length(Person where (each.behavioral_state = "atascado"));
        monitor "Usando Escalera" value: length(Person where (each.behavioral_state = "usando_escalera"));
        monitor "──────────────" value: "";
        monitor "Evacuados (A Salvo)" value: N_floor0 + N_floor1 - length(Person);
        monitor "🪜 Total en Colas" value: sum(StairArea collect length(each.en_espera));
        monitor "🪜 Total Usando Escaleras" value: sum(StairArea collect length(each.on_stair));
        monitor "──────────────" value: "";
        monitor "⏱️ Tiempo desde alarma" value: (alarm_active) ? (time - tiempo_inicio_evacuacion) : 0.0;
        monitor "🚧 Total atascados" value: total_atascados;
        monitor "🏢 Evacuados Piso 0" value: evacuados_por_piso[0];
        monitor "🏢 Evacuados Piso 1" value: evacuados_por_piso[1];
	}
}