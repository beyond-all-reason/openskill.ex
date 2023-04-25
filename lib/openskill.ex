defmodule Openskill do
  @moduledoc """
    Openskill is a library for calculating skill ratings.
  """

  alias Openskill.{Environment, Util}

  @env %Environment{}

  @doc """
  Creates an initialized rating.

  ## Examples

      iex> Openskill.rating
      { 25, 8.333 }

      iex> Openskill.rating(1000, 32)
      { 1000, 32 }
  """
  def rating(mu \\ nil, sigma \\ nil) do
    {mu || @env.mu, sigma || @env.sigma}
  end

  def ordinal({mu, sigma}) do
    mu - @env.z * sigma
  end

  def rate(rating_groups, options \\ []) do
    defaults = [
      weights: Util.default_weights(rating_groups),
      ranks: Util.default_ranks(rating_groups),
      model: Openskill.PlackettLuce,
      tau: @env.tau,
      prevent_sigma_increase: @env.prevent_sigma_increase
    ]

    options = Keyword.merge(defaults, options) |> Enum.into(%{})

    new_rating_groups =
      Enum.map(rating_groups, fn team ->
        Enum.map(team, fn {mu, sigma} ->
          {mu, Math.sqrt(sigma ** 2 + options.tau ** 2)}
        end)
      end)

    output = options.model.rate(new_rating_groups, options)

    if options.tau > 0 and options.prevent_sigma_increase do
      Enum.zip(rating_groups, output)
      |> Enum.map(fn {old_team, new_team} ->
        Enum.zip(old_team, new_team)
        |> Enum.map(fn {{_old_mu, old_sigma}, {new_mu, new_sigma}} ->
          {new_mu, min(old_sigma, new_sigma)}
        end)
      end)
    else
      output
    end
  end
end
