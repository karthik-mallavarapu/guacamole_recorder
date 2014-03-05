module GuacamoleParser

  # Parse the instructions received from the server, identify 
  # the opcode and return relevant arguments.
  def parse(instruction)
    elements = instruction.split(',')
    opcode = (elements[0].split('.'))[1]
    args = elements[1, (elements.size - 1)]
    args.map! {|a| a = a.split('.')[1]}

    case opcode
    
    when "png"
      return {opcode: 'png', dst_layer: args[1], data: args[4], 
        x_offset: args[2], y_offset: args[3]}
    when "sync"
      return {opcode: 'sync', data: args[0]}
    when "args"
      return {opcode: 'args', count: args.size}  
    when "copy"
      return {opcode: 'copy', src_layer: args[0], src_x_offset: args[1], 
        src_y_offset: args[2], src_width: args[3], src_height: args[4], 
        dst_layer: args[6], x_offset: args[7], y_offset: args[8] }
    when "cursor"
      return {opcode: 'cursor', src_layer: args[2], x_offset: args[0], 
        y_offset: args[1], src_x_offset: args[3], src_y_offset: args[4], 
        width: args[5], height: args[6]}
    when "rect"
      return {opcode: 'rect', dst_layer: args[0], x_offset: args[1], 
        y_offset: args[2], width: args[3], height: args[4]}    
    when "cfill"
      return {opcode: 'cfill', src_layer: args[1]}  
    when "transfer"
      return {opcode: 'transfer', src_layer: args[0], src_x_offset: args[1], 
        src_y_offset: args[2], src_width: args[3], src_height: args[4], 
        dst_layer: args[6], x_offset: args[7], y_offset: args[8] }  
    when "size"
      return {opcode: 'size', src_layer: args[0], width: args[1], height: args[2]}
    else
      puts "#{opcode}: #{args}"  
    end
  end

end