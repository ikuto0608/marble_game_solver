require 'time'
require "json"
require 'redis'

EMPTY = 0
FILLED = 1
NON_FIELD = 9
CENTER = [0, 0]
NON_FIELD_ARRAY = [
                    [-3, -3], [-2, -3], [-3, -2], [-2, -2],
                    [2, -3], [3, -3], [2, -2], [3, -2],
                    [-3, 2], [-2, 2], [-3, 3], [-2, 3],
                    [2, 2], [3, 2], [2, 3], [3, 3]
                  ]

@current_field = {}
@record = []

def initialize_field
  6.downto(0) do |y_index|
    7.times do |x_index|
      unless NON_FIELD_ARRAY.include?([x_index - 3, y_index - 3])
        unless CENTER == [x_index - 3, y_index - 3]
          @current_field[[x_index - 3, y_index - 3]] = FILLED
        else
          @current_field[[x_index - 3, y_index - 3]] = EMPTY
        end
      else
        @current_field[[x_index - 3, y_index - 3]] = NON_FIELD
      end
    end
  end
end

def play_game
  redis = Redis.new
  keys = @current_field.select{|key, value| value == FILLED }
                       .keys

  keys.each do |key|
    board_history = []
    inverse_field_hash = inverse_field
    board_history_key = [
                          @current_field.values.join.to_i,
                          rotation_field(90, @current_field).values.join.to_i,
                          rotation_field(180, @current_field).values.join.to_i,
                          rotation_field(270, @current_field).values.join.to_i,
                          inverse_field_hash.values.join.to_i,
                          rotation_field(90, inverse_field_hash).values.join.to_i,
                          rotation_field(180, inverse_field_hash).values.join.to_i,
                          rotation_field(270, inverse_field_hash).values.join.to_i,
                        ].min
    row_board_history = redis.get(board_history_key)
    unless row_board_history.nil?
      board_history = JSON.parse(row_board_history)
    end

    next if board_history.include?(key)
    break if complete_game?

    field_array = @current_field.dup
    record = @record.dup

    if can_jump_right?([key[0], key[1]])
      jump_right([key[0], key[1]])
      play_game
    end

    break if complete_game?
    @current_field = field_array.dup
    @record = record.dup

    if can_jump_down?([key[0], key[1]])
      jump_down([key[0], key[1]])
      play_game
    end

    break if complete_game?
    @current_field = field_array.dup
    @record = record.dup

    if can_jump_left?([key[0], key[1]])
      jump_left([key[0], key[1]])
      play_game
    end

    break if complete_game?
    @current_field = field_array.dup
    @record = record.dup

    if can_jump_up?([key[0], key[1]])
      jump_up([key[0], key[1]])
      play_game
    end

    board_history << key
    redis.set(board_history_key, board_history.to_json)
  end
end

def complete_game?
  return @current_field.values.count(FILLED) == 1
end

def jump_right(spot)
  @current_field[[spot[0], spot[1]]] = EMPTY
  @current_field[[spot[0] + 1, spot[1]]] = EMPTY
  @current_field[[spot[0] + 2, spot[1]]] = FILLED

  @record.push("[#{spot[0]}, #{spot[1]}] jump Right!")
end

def jump_left(spot)
  @current_field[[spot[0], spot[1]]] = EMPTY
  @current_field[[spot[0] - 1, spot[1]]] = EMPTY
  @current_field[[spot[0] - 2, spot[1]]] = FILLED

  @record.push("[#{spot[0]}, #{spot[1]}] jump Left!")
end

def jump_up(spot)
  @current_field[[spot[0], spot[1]]] = EMPTY
  @current_field[[spot[0], spot[1] + 1]] = EMPTY
  @current_field[[spot[0], spot[1] + 2]] = FILLED

  @record.push("[#{spot[0]}, #{spot[1]}] jump Up!")
end

def jump_down(spot)
  @current_field[[spot[0], spot[1]]] = EMPTY
  @current_field[[spot[0], spot[1] - 1]] = EMPTY
  @current_field[[spot[0], spot[1] - 2]] = FILLED

  @record.push("[#{spot[0]}, #{spot[1]}] jump Down!")
end

def can_jump_right?(spot)
  return false if !filled_place?(spot)

  next_spot = [spot[0] + 1, spot[1]]
  return false if !filled_place?(next_spot)

  next_next_spot = [spot[0] + 2, spot[1]]
  return false if !empty_place?(next_next_spot)

  return true
end

def can_jump_left?(spot)
  return false if !filled_place?(spot)

  next_spot = [spot[0] - 1, spot[1]]
  return false if !filled_place?(next_spot)

  next_next_spot = [spot[0] - 2, spot[1]]
  return false if !empty_place?(next_next_spot)

  return true
end

def can_jump_up?(spot)
  return false if !filled_place?(spot)

  next_spot = [spot[0], spot[1] + 1]
  return false if !filled_place?(next_spot)

  next_next_spot = [spot[0], spot[1] + 2]
  return false if !empty_place?(next_next_spot)

  return true
end

def can_jump_down?(spot)
  return false if !filled_place?(spot)

  next_spot = [spot[0], spot[1] - 1]
  return false if !filled_place?(next_spot)

  next_next_spot = [spot[0], spot[1] - 2]
  return false if !empty_place?(next_next_spot)

  return true
end

def filled_place?(spot)
  return !@current_field[[spot[0], spot[1]]].nil? && @current_field[[spot[0], spot[1]]] == FILLED
end

def empty_place?(spot)
  return !@current_field[[spot[0], spot[1]]].nil? && @current_field[[spot[0], spot[1]]] == EMPTY
end

def rotation_field(degrees, field)
  radians = degrees * Math::PI / 180

  field.keys.inject({}) do |h, key|
    coordinate = [
                    (key[0] * Math.cos(radians)) - (key[1] * Math.sin(radians)),
                    (key[0] * Math.sin(radians)) + (key[1] * Math.cos(radians))
                  ]
    h[coordinate] = field[key]
    h
  end
end

def inverse_field
  inverse_values = @current_field.values.reverse
  index = 0
  @current_field.keys.inject({}) do |h, value|
    h[value] = inverse_values[index]
    index += 1
    h
  end
end

puts "Start at: #{Time.now}"
initialize_field
play_game

@record.each do |r|
  puts r
end

puts "Finish at: #{Time.now}"
