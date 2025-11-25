model NavNode

species NavNode {
    int id;
    int floor;
    list<NavNode> neighbors <- [];
    //point location;
    
    aspect default {
    	if (false){
    		draw circle(0.1) color: #purple;
    	
    	
	    	if (length(neighbors) > 0){
	    		loop n over: neighbors {
	    			draw line(location, n.location) color: #darkgray width: 0.08;
	    		}
	    	}
    	}
    }
}

species CorridorNode parent: NavNode {
    geometry corridor_area;
}