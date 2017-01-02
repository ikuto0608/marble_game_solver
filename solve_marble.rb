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

@current_field_hash = {}
@record = []
@completed = false

def initialize_field
  6.downto(0) do |y|
    7.times do |x|
      unless NON_FIELD_ARRAY.include?([x - 3, y - 3])
        unless CENTER == [x - 3, y - 3]
          @current_field_hash[[x - 3, y - 3]] = FILLED
        else
          @current_field_hash[[x - 3, y - 3]] = EMPTY
        end
      else
        @current_field_hash[[x - 3, y - 3]] = NON_FIELD
      end
    end
  end
end

def play_game
  redis = Redis.new
  filled_coordinates = @current_field_hash.select{|key, value| value == FILLED }
                                          .keys
  filled_coordinates.each do |coordinate|
    field_hash = @current_field_hash.dup
    record = @record.dup

    board_history_key = summarize_board_history_key
    board_history = redis.get(board_history_key) || []
    if !board_history.empty?
      board_history = JSON.parse(board_history)
      next if board_history.include?(coordinate)
    end

    if can_jump_right?([coordinate[0], coordinate[1]])
      jump_right([coordinate[0], coordinate[1]])
      play_game
      break if complete_game?
    end

    @current_field_hash = field_hash.dup
    @record = record.dup

    if can_jump_down?([coordinate[0], coordinate[1]])
      jump_down([coordinate[0], coordinate[1]])
      play_game
      break if complete_game?
    end

    @current_field_hash = field_hash.dup
    @record = record.dup

    if can_jump_left?([coordinate[0], coordinate[1]])
      jump_left([coordinate[0], coordinate[1]])
      play_game
      break if complete_game?
    end

    @current_field_hash = field_hash.dup
    @record = record.dup

    if can_jump_up?([coordinate[0], coordinate[1]])
      jump_up([coordinate[0], coordinate[1]])
      play_game
      break if complete_game?
    end

    board_history << coordinate
    redis.set(board_history_key, board_history.to_json)
  end
end

def complete_game?
  return true if @completed

  if @current_field_hash.values.count(FILLED) == 1
    @completed = true
    return true
  else
    return false
  end
end

def jump_right(coordinate)
  @current_field_hash[[coordinate[0], coordinate[1]]] = EMPTY
  @current_field_hash[[coordinate[0] + 1, coordinate[1]]] = EMPTY
  @current_field_hash[[coordinate[0] + 2, coordinate[1]]] = FILLED

  @record.push("Jump RIGHT at (#{coordinate[0]}, #{coordinate[1]}).")
end

def jump_left(coordinate)
  @current_field_hash[[coordinate[0], coordinate[1]]] = EMPTY
  @current_field_hash[[coordinate[0] - 1, coordinate[1]]] = EMPTY
  @current_field_hash[[coordinate[0] - 2, coordinate[1]]] = FILLED

  @record.push("Jump LEFT at (#{coordinate[0]}, #{coordinate[1]}).")
end

def jump_up(coordinate)
  @current_field_hash[[coordinate[0], coordinate[1]]] = EMPTY
  @current_field_hash[[coordinate[0], coordinate[1] + 1]] = EMPTY
  @current_field_hash[[coordinate[0], coordinate[1] + 2]] = FILLED

  @record.push("Jump UP at (#{coordinate[0]}, #{coordinate[1]}).")
end

def jump_down(coordinate)
  @current_field_hash[[coordinate[0], coordinate[1]]] = EMPTY
  @current_field_hash[[coordinate[0], coordinate[1] - 1]] = EMPTY
  @current_field_hash[[coordinate[0], coordinate[1] - 2]] = FILLED

  @record.push("Jump DOWN at (#{coordinate[0]}, #{coordinate[1]}).")
end

def can_jump_right?(coordinate)
  return false if !filled_place?(coordinate)

  next_coordinate = [coordinate[0] + 1, coordinate[1]]
  return false if !filled_place?(next_coordinate)

  next_next_coordinate = [coordinate[0] + 2, coordinate[1]]
  return false if !empty_place?(next_next_coordinate)

  return true
end

def can_jump_left?(coordinate)
  return false if !filled_place?(coordinate)

  next_coordinate = [coordinate[0] - 1, coordinate[1]]
  return false if !filled_place?(next_coordinate)

  next_next_coordinate = [coordinate[0] - 2, coordinate[1]]
  return false if !empty_place?(next_next_coordinate)

  return true
end

def can_jump_up?(coordinate)
  return false if !filled_place?(coordinate)

  next_coordinate = [coordinate[0], coordinate[1] + 1]
  return false if !filled_place?(next_coordinate)

  next_next_coordinate = [coordinate[0], coordinate[1] + 2]
  return false if !empty_place?(next_next_coordinate)

  return true
end

def can_jump_down?(coordinate)
  return false if !filled_place?(coordinate)

  next_coordinate = [coordinate[0], coordinate[1] - 1]
  return false if !filled_place?(next_coordinate)

  next_next_coordinate = [coordinate[0], coordinate[1] - 2]
  return false if !empty_place?(next_next_coordinate)

  return true
end

def filled_place?(coordinate)
  !@current_field_hash[[coordinate[0], coordinate[1]]].nil? &&
    @current_field_hash[[coordinate[0], coordinate[1]]] == FILLED
end

def empty_place?(coordinate)
  !@current_field_hash[[coordinate[0], coordinate[1]]].nil? &&
    @current_field_hash[[coordinate[0], coordinate[1]]] == EMPTY
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
  inverse_values = @current_field_hash.values.reverse
  index = 0
  @current_field_hash.keys.inject({}) do |h, value|
    h[value] = inverse_values[index]
    index += 1
    h
  end
end

def summarize_board_history_key
  inverse_field_hash = inverse_field
  [
    @current_field_hash.values.join.to_i,
    rotation_field(90, @current_field_hash).values.join.to_i,
    rotation_field(180, @current_field_hash).values.join.to_i,
    rotation_field(270, @current_field_hash).values.join.to_i,
    inverse_field_hash.values.join.to_i,
    rotation_field(90, inverse_field_hash).values.join.to_i,
    rotation_field(180, inverse_field_hash).values.join.to_i,
    rotation_field(270, inverse_field_hash).values.join.to_i,
  ].min
end


puts "Start at: #{Time.now}"
initialize_field
play_game
puts "Finish at: #{Time.now}"
@record.each_with_index do |r, index|
  puts "#{index + 1},#{r}"
end
