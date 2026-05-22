# frozen_string_literal: true

class KnownPeopleController < ApplicationController
  before_action :set_known_person, only: %i[show edit update destroy]

  def index
    @known_people = Current.user.known_people.order(:name)
  end

  def show
  end

  def new
    @known_person = KnownPerson.new
  end

  def create
    @known_person = Current.user.known_people.build(known_person_params)

    if @known_person.save
      redirect_to @known_person, notice: "#{@known_person.name} was added as a known person."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @known_person.update(known_person_params)
      redirect_to @known_person, notice: "#{@known_person.name} was updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @known_person.name
    @known_person.destroy
    redirect_to known_people_path, notice: "#{name} was removed."
  end

  private

  def set_known_person
    @known_person = Current.user.known_people.find(params[:id])
  end

  def known_person_params
    params.require(:known_person).permit(:name, :reference_image_url, :reference_image, :notes)
  end
end
