extends Sprite2D

@export var speed: float = 300.0

func _process(delta):
	var velocity = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		velocity.x += 1
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		velocity.x -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		velocity.y += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		velocity.y -= 1
	
	if velocity.length() > 0:
		velocity = velocity.normalized()
	
	position += velocity * speed * delta
